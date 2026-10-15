defmodule Dcmix.Network.SCP do
  @moduledoc """
  Serves one association accepted on a TCP socket, as an SCP.

  `serve/2` reads the A-ASSOCIATE-RQ, answers it with an A-ASSOCIATE-AC or
  -RJ (see `Dcmix.Network.Negotiation`), then answers DIMSE requests until
  the requestor releases or aborts the association. It supports the
  Verification SOP Class: each C-ECHO-RQ is answered with success.

  It runs in the calling process and uses the socket in passive mode.
  `Dcmix.Network.Listener` calls it for each connection it accepts.
  """

  require Logger

  alias Dcmix.Network.{Association, DIMSE, Negotiation, PDU, SOPClassUID}
  alias Dcmix.Parser.TransferSyntax

  require Dcmix.Network.DIMSE.CommandField, as: CommandField
  require Dcmix.Network.DIMSE.Status, as: Status

  @default_max_pdu_length 16_384
  @default_timeout 60_000

  # The PDU stream is out of step after these, so it must not be read again
  @desync_errors [:pdu_too_large, :pdu_read_timeout]

  @doc """
  Serves the association a requestor opens on `socket`, until it ends.

  ## Options
  - `:ae_title` - our AE title; a requestor calling any other is rejected
    (required)
  - `:max_pdu_length` - the largest PDU we accept (default: 16384)
  - `:timeout` - how long to wait for the requestor's next PDU, in ms,
    before aborting (default: 60000)

  ## Returns
  - `:ok` when the requestor releases the association
  - `{:error, {:association_rejected, rejection}}` when it is rejected
  - `{:error, reason}` when it is aborted or the connection fails
  """
  @spec serve(:gen_tcp.socket(), keyword()) :: :ok | {:error, term()}
  def serve(socket, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_pdu_length = Keyword.get(opts, :max_pdu_length, @default_max_pdu_length)

    with {:ok, rq} <- receive_associate_rq(socket, timeout) do
      rq
      |> Negotiation.negotiate(
        ae_title: Keyword.fetch!(opts, :ae_title),
        abstract_syntaxes: abstract_syntaxes()
      )
      |> answer(socket, rq, max_pdu_length, timeout)
    end
  end

  @doc """
  Reads the A-ASSOCIATE-RQ a requestor sends on `socket` and rejects it with
  `rejection`, e.g. `Dcmix.Network.Negotiation.local_limit_exceeded/0`.

  ## Options
  - `:timeout` - how long to wait for the A-ASSOCIATE-RQ, in ms
    (default: 60000)
  """
  @spec refuse(:gen_tcp.socket(), Negotiation.rejection(), keyword()) :: {:error, term()}
  def refuse(socket, rejection, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    with {:ok, rq} <- receive_associate_rq(socket, timeout) do
      reject(socket, rq, rejection)
    end
  end

  # Abstract syntaxes we accept, each with its transfer syntaxes in our order
  # of preference
  defp abstract_syntaxes do
    %{
      SOPClassUID.verification() => [
        TransferSyntax.explicit_vr_little_endian(),
        TransferSyntax.implicit_vr_little_endian()
      ]
    }
  end

  # ===========================================================================
  # Association establishment
  # ===========================================================================

  defp receive_associate_rq(socket, timeout) do
    case Association.receive_pdu(%Association{socket: socket}, timeout) do
      {:ok, {:associate_rq, rq}} ->
        {:ok, rq}

      {:ok, other} ->
        abort(%Association{socket: socket})
        {:error, {:unexpected_pdu, other}}

      {:error, reason} = error ->
        close_after_error(%Association{socket: socket}, reason)
        error
    end
  end

  defp answer({:reject, rejection}, socket, rq, _max_pdu_length, _timeout),
    do: reject(socket, rq, rejection)

  defp answer({:accept, contexts}, socket, rq, max_pdu_length, timeout) do
    pdu = PDU.encode_associate_ac(rq, contexts, max_pdu_length: max_pdu_length)

    assoc = %Association{
      socket: socket,
      max_pdu_length: rq.max_pdu_length,
      local_max_pdu_length: max_pdu_length,
      presentation_contexts: Enum.filter(contexts, &(&1.result == 0))
    }

    case :gen_tcp.send(socket, pdu) do
      :ok -> serve_dimse(assoc, timeout, [])
      {:error, reason} -> {:error, {:send_failed, reason}}
    end
  end

  defp reject(socket, rq, %{result: result, source: source, reason: reason} = rejection) do
    Logger.info(
      "[SCP] Rejected association from #{rq.calling_ae_title} to #{rq.called_ae_title}: " <>
        "result #{result}, source #{source}, reason #{reason}"
    )

    _ = :gen_tcp.send(socket, PDU.encode_associate_rj(result, source, reason))
    :gen_tcp.close(socket)
    {:error, {:association_rejected, rejection}}
  end

  # ===========================================================================
  # DIMSE
  # ===========================================================================

  # `fragments` collects the PDVs of a command that spans several of them
  defp serve_dimse(assoc, timeout, fragments) do
    case Association.receive_pdu(assoc, timeout) do
      {:ok, {:p_data, pdvs}} ->
        handle_pdvs(assoc, timeout, fragments, pdvs)

      {:ok, :release_rq} ->
        _ = :gen_tcp.send(assoc.socket, PDU.encode_release_rp())
        :gen_tcp.close(assoc.socket)
        :ok

      {:ok, {:abort, _}} ->
        :gen_tcp.close(assoc.socket)
        {:error, :association_aborted}

      {:ok, other} ->
        abort(assoc)
        {:error, {:unexpected_pdu, other}}

      {:error, reason} = error ->
        close_after_error(assoc, reason)
        error
    end
  end

  defp handle_pdvs(assoc, timeout, fragments, []), do: serve_dimse(assoc, timeout, fragments)

  defp handle_pdvs(assoc, timeout, fragments, [pdv | rest]) do
    cond do
      not accepted_context?(assoc, pdv.context_id) ->
        abort(assoc)
        {:error, {:unknown_presentation_context, pdv.context_id}}

      not pdv.is_command ->
        abort(assoc)
        {:error, :unexpected_data_set}

      not pdv.is_last ->
        handle_pdvs(assoc, timeout, [fragments, pdv.data], rest)

      true ->
        with {:ok, command} <- decode_command([fragments, pdv.data]),
             :ok <- handle_command(assoc, pdv.context_id, command) do
          handle_pdvs(assoc, timeout, [], rest)
        else
          {:error, _} = error ->
            abort(assoc)
            error
        end
    end
  end

  defp decode_command(fragments), do: DIMSE.decode_command(IO.iodata_to_binary(fragments))

  defp handle_command(assoc, context_id, %{command_field: CommandField.c_echo_rq()} = command) do
    rsp = DIMSE.build_cecho_rsp(command.message_id, Status.success())
    Association.send_pdata(assoc, context_id, true, rsp)
  end

  defp handle_command(_assoc, _context_id, command),
    do: {:error, {:unsupported_command, command.command_field}}

  defp accepted_context?(assoc, context_id),
    do: Enum.any?(assoc.presentation_contexts, &(&1.id == context_id))

  # ===========================================================================
  # Closing
  # ===========================================================================

  defp close_after_error(assoc, reason) when reason in @desync_errors, do: abort(assoc)
  defp close_after_error(assoc, {:recv_failed, :timeout}), do: abort(assoc)
  defp close_after_error(assoc, _reason), do: :gen_tcp.close(assoc.socket)

  defp abort(assoc), do: Association.abort(assoc)
end
