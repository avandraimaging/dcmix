defmodule Dcmix.Network.CEcho do
  @moduledoc """
  High-level DICOM C-ECHO SCU operation, like dcmtk's `echoscu`.

  Verifies that a remote DICOM node accepts an association for the
  Verification SOP Class and answers a C-ECHO-RQ with success.
  """

  alias Dcmix.Network.Association
  alias Dcmix.Network.DIMSE
  alias Dcmix.Parser.TransferSyntax

  # Verification SOP Class
  @verification "1.2.840.10008.1.1"

  @cecho_rsp 0x8030
  @message_id 1

  # The PDU stream is out of step after these, so it must not be read again
  @desync_errors [:pdu_too_large, :pdu_read_timeout]

  @doc """
  Sends a C-ECHO to a DICOM node.

  ## Parameters

  - `addr` - Server address as `"host:port"`
  - `opts` - Connection options:
    - `:calling_ae_title` - Calling AE Title (default: `"DCMIX"`)
    - `:called_ae_title` - Called AE Title (default: `"ANY-SCP"`)
    - `:timeout` - TCP timeout in ms (default: 30000)

  ## Returns

  - `:ok` when the node answers with success
  - `{:error, {:cecho_failed, status}}` when it answers with another status
  - `{:error, reason}` when the association or the exchange fails

  ## Examples

      :ok = Dcmix.Network.CEcho.echo("localhost:4242", called_ae_title: "PACS_AE")
  """
  @spec echo(String.t(), keyword()) :: :ok | {:error, term()}
  def echo(addr, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    with {:ok, assoc} <-
           Association.request(addr,
             calling_ae_title: Keyword.get(opts, :calling_ae_title, "DCMIX"),
             called_ae_title: Keyword.get(opts, :called_ae_title, "ANY-SCP"),
             abstract_syntaxes: [@verification],
             transfer_syntaxes: [TransferSyntax.implicit_vr_little_endian()],
             timeout: timeout
           ) do
      result = run_echo(assoc, timeout)
      close_association(assoc, result)
      result
    end
  end

  defp run_echo(assoc, timeout) do
    with {:ok, pc} <- Association.accepted_context(assoc, @verification),
         :ok <- Association.send_pdata(assoc, pc.id, true, DIMSE.build_cecho_rq(@message_id)),
         {:ok, command} <- receive_command(assoc, timeout, []) do
      check_response(command)
    end
  end

  # The response command may arrive as several PDV fragments
  defp receive_command(assoc, timeout, fragments) do
    case Association.receive_pdu(assoc, timeout) do
      {:ok, {:p_data, pdvs}} -> collect_command(assoc, timeout, fragments, pdvs)
      {:ok, {:abort, _}} -> {:error, :association_aborted}
      {:ok, :release_rq} -> {:error, :unexpected_release}
      {:ok, other} -> {:error, {:unexpected_pdu, other}}
      {:error, _} = error -> error
    end
  end

  defp collect_command(assoc, timeout, fragments, pdvs) do
    fragments = fragments ++ for(pdv <- pdvs, pdv.is_command, do: pdv.data)

    if Enum.any?(pdvs, &(&1.is_command and &1.is_last)),
      do: DIMSE.decode_command(IO.iodata_to_binary(fragments)),
      else: receive_command(assoc, timeout, fragments)
  end

  defp check_response(%{
         command_field: @cecho_rsp,
         message_id_being_responded_to: @message_id,
         status: status
       }) do
    case DIMSE.status_meaning(status) do
      :success -> :ok
      _other -> {:error, {:cecho_failed, status}}
    end
  end

  defp check_response(command), do: {:error, {:unexpected_response, command}}

  defp close_association(_assoc, {:error, :association_aborted}), do: :ok

  defp close_association(assoc, {:error, reason}) when reason in @desync_errors,
    do: Association.abort(assoc)

  defp close_association(assoc, _result), do: Association.release(assoc)
end
