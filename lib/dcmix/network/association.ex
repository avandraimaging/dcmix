defmodule Dcmix.Network.Association do
  @moduledoc """
  DICOM Association management for SCU (Service Class User) connections.

  Manages the TCP connection lifecycle and DICOM Upper Layer association
  negotiation. Uses `:gen_tcp` directly with synchronous I/O.

  ## Workflow

  1. `request/2` - Open TCP connection and negotiate association
  2. `send_pdata/4` - Send P-DATA PDUs (command or data)
  3. `receive_pdu/1` - Receive and decode the next PDU
  4. `release/1` - Gracefully release the association
  """

  require Logger

  alias Dcmix.Network.PDU
  alias Dcmix.Parser.TransferSyntax

  @type t :: %__MODULE__{
          socket: :gen_tcp.socket(),
          max_pdu_length: non_neg_integer(),
          local_max_pdu_length: non_neg_integer(),
          presentation_contexts: [PDU.accepted_context()]
        }

  # max_pdu_length is the peer's receive limit; local_max_pdu_length is ours
  defstruct [:socket, :max_pdu_length, local_max_pdu_length: 0, presentation_contexts: []]

  # Default TCP recv timeout (30 seconds)
  @default_timeout 30_000

  # PDU header size
  @pdu_header_size 6

  @p_data_tf 0x04

  # PDV item overhead: item length (4) + context ID (1) + control header (1)
  @pdv_overhead 6

  # Study Root Q/R Information Model - FIND
  @study_root_qr_find "1.2.840.10008.5.1.4.1.2.2.1"

  @doc """
  Establishes a DICOM association with a remote SCP.

  ## Parameters
  - `addr` - Server address as `"host:port"` string
  - `opts` - Options:
    - `:calling_ae_title` - Calling AE Title (default: `"DCMIX"`)
    - `:called_ae_title` - Called AE Title (default: `"ANY-SCP"`)
    - `:abstract_syntaxes` - List of abstract syntax UIDs (default: Study Root Q/R Find)
    - `:transfer_syntaxes` - List of transfer syntax UIDs to propose
    - `:presentation_contexts` - Per-context proposals, overriding
      `:abstract_syntaxes`/`:transfer_syntaxes`. Each is a map with
      `:abstract_syntax`, `:transfer_syntaxes` and optional boolean `:scu_role`
      and `:scp_role`; giving either role adds an SCP/SCU Role Selection item
      for that abstract syntax
    - `:timeout` - TCP timeout in ms (default: 30000)
    - `:max_pdu_length` - Max PDU length to propose (default: 16384)

  Each returned presentation context carries the `:abstract_syntax` that was
  proposed for its ID, plus `:scu_role`/`:scp_role` as negotiated by the
  acceptor (`nil` when it returned no role selection for that syntax).

  ## Returns
  - `{:ok, association}` on successful negotiation
  - `{:error, reason}` on failure
  """
  @spec request(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def request(addr, opts \\ []) do
    calling_ae = Keyword.get(opts, :calling_ae_title, "DCMIX")
    called_ae = Keyword.get(opts, :called_ae_title, "ANY-SCP")

    proposed = proposed_contexts(opts)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_pdu_length = Keyword.get(opts, :max_pdu_length, 16_384)

    with {:ok, {host, port}} <- parse_address(addr),
         {:ok, socket} <- connect(host, port, timeout),
         :ok <- send_associate_rq(socket, calling_ae, called_ae, proposed, max_pdu_length),
         {:ok, result} <- receive_associate_response(socket, timeout) do
      {:ok,
       %__MODULE__{
         socket: socket,
         max_pdu_length: result.max_pdu_length,
         local_max_pdu_length: max_pdu_length,
         presentation_contexts: annotate_contexts(result, proposed)
       }}
    end
  end

  @doc """
  Returns the first accepted presentation context, or error if none.
  """
  @spec accepted_context(t()) :: {:ok, PDU.accepted_context()} | {:error, term()}
  def accepted_context(%__MODULE__{presentation_contexts: contexts}) do
    case Enum.find(contexts, fn pc -> pc.result == 0 end) do
      nil -> {:error, :no_accepted_presentation_context}
      pc -> {:ok, pc}
    end
  end

  @doc """
  Returns the first accepted presentation context for `abstract_syntax`.
  """
  @spec accepted_context(t(), String.t()) :: {:ok, PDU.accepted_context()} | {:error, term()}
  def accepted_context(%__MODULE__{presentation_contexts: contexts}, abstract_syntax) do
    case Enum.find(contexts, &(&1.result == 0 and &1[:abstract_syntax] == abstract_syntax)) do
      nil -> {:error, :no_accepted_presentation_context}
      pc -> {:ok, pc}
    end
  end

  @doc """
  Sends the given command or data set as P-DATA PDUs.

  Data larger than the peer's maximum PDU length is split into several
  PDVs, with the last-fragment bit set only on the final one.
  """
  @spec send_pdata(t(), non_neg_integer(), boolean(), binary()) :: :ok | {:error, term()}
  def send_pdata(%__MODULE__{socket: socket} = assoc, context_id, is_command, data) do
    data
    |> fragments(max_fragment_size(assoc))
    |> Enum.reduce_while(:ok, fn {fragment, is_last}, :ok ->
      pdu = PDU.encode_p_data(context_id, is_command, is_last, fragment)

      case tcp_send(socket, pdu) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Receives and decodes the next PDU from the remote peer.

  A timeout before any byte of the PDU arrives returns
  `{:error, {:recv_failed, :timeout}}` and leaves the connection usable.
  A timeout after the header returns `{:error, :pdu_read_timeout}`; the PDU
  boundary is then lost and the association must be aborted.

  A P-DATA-TF PDU longer than the maximum length we proposed (PS3.8 9.3.1;
  0 means unlimited) returns `{:error, :pdu_too_large}` without reading its
  payload; the association must be aborted.
  """
  @spec receive_pdu(t(), non_neg_integer()) :: {:ok, PDU.pdu()} | {:error, term()}
  def receive_pdu(%__MODULE__{socket: socket} = assoc, timeout \\ @default_timeout) do
    with {:ok, header_bytes} <- tcp_recv(socket, @pdu_header_size, timeout),
         {:ok, type, length} <- PDU.decode_header(header_bytes),
         :ok <- check_pdu_length(assoc, type, length),
         {:ok, payload} <- recv_payload(socket, length, timeout) do
      case PDU.decode_pdu(header_bytes <> payload) do
        {:ok, pdu, _rest} -> {:ok, pdu}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Gracefully releases the association.
  """
  @spec release(t()) :: :ok
  def release(%__MODULE__{socket: socket}) do
    pdu = PDU.encode_release_rq()
    _ = tcp_send(socket, pdu)

    # Try to receive the release response, but don't fail if we can't
    case tcp_recv(socket, @pdu_header_size, 5_000) do
      {:ok, header} ->
        case PDU.decode_header(header) do
          {:ok, _type, length} ->
            _ = tcp_recv(socket, length, 5_000)
            :ok

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  after
    :gen_tcp.close(socket)
  end

  @doc """
  Aborts the association.
  """
  @spec abort(t()) :: :ok
  def abort(%__MODULE__{socket: socket}) do
    pdu = PDU.encode_abort()
    _ = tcp_send(socket, pdu)
    :gen_tcp.close(socket)
    :ok
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp parse_address(addr) do
    case String.split(addr, ":") do
      [host, port_str] ->
        case Integer.parse(port_str) do
          {port, ""} ->
            host_charlist = String.to_charlist(host)
            {:ok, {host_charlist, port}}

          _ ->
            {:error, {:invalid_port, port_str}}
        end

      _ ->
        {:error, {:invalid_address, addr}}
    end
  end

  defp connect(host, port, timeout) do
    opts = [:binary, active: false, packet: :raw]

    case :gen_tcp.connect(host, port, opts, timeout) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:error, {:connection_failed, reason}}
    end
  end

  defp proposed_contexts(opts) do
    opts
    |> Keyword.get_lazy(:presentation_contexts, fn -> legacy_contexts(opts) end)
    |> Enum.with_index(1)
    # Presentation context IDs must be odd numbers
    |> Enum.map(fn {pc, idx} -> Map.put(pc, :id, idx * 2 - 1) end)
  end

  defp legacy_contexts(opts) do
    transfer_syntaxes =
      Keyword.get(opts, :transfer_syntaxes, [
        TransferSyntax.implicit_vr_little_endian(),
        TransferSyntax.explicit_vr_little_endian()
      ])

    opts
    |> Keyword.get(:abstract_syntaxes, [@study_root_qr_find])
    |> Enum.map(&%{abstract_syntax: &1, transfer_syntaxes: transfer_syntaxes})
  end

  # Roles are negotiated per SOP class, not per context
  defp role_selections(proposed) do
    proposed
    |> Enum.filter(&(Map.has_key?(&1, :scu_role) or Map.has_key?(&1, :scp_role)))
    |> Enum.uniq_by(& &1.abstract_syntax)
    |> Enum.map(fn pc ->
      %{
        sop_class_uid: pc.abstract_syntax,
        scu_role: Map.get(pc, :scu_role, false),
        scp_role: Map.get(pc, :scp_role, false)
      }
    end)
  end

  # The AC's context items carry no abstract syntax; recover it by ID
  defp annotate_contexts(result, proposed) do
    syntax_by_id = Map.new(proposed, &{&1.id, &1.abstract_syntax})
    roles = Map.new(result.role_selections, &{&1.sop_class_uid, &1})

    Enum.map(result.presentation_contexts, fn pc ->
      abstract_syntax = Map.get(syntax_by_id, pc.id)
      role = Map.get(roles, abstract_syntax, %{})

      Map.merge(pc, %{
        abstract_syntax: abstract_syntax,
        scu_role: Map.get(role, :scu_role),
        scp_role: Map.get(role, :scp_role)
      })
    end)
  end

  defp send_associate_rq(socket, calling_ae, called_ae, proposed, max_pdu_length) do
    pdu =
      PDU.encode_associate_rq(calling_ae, called_ae, proposed,
        max_pdu_length: max_pdu_length,
        role_selections: role_selections(proposed)
      )

    tcp_send(socket, pdu)
  end

  # The limit covers the PDU's variable field, i.e. the header's length value
  defp check_pdu_length(%__MODULE__{local_max_pdu_length: max}, @p_data_tf, length)
       when max > 0 and length > max,
       do: {:error, :pdu_too_large}

  defp check_pdu_length(_assoc, _type, _length), do: :ok

  defp recv_payload(socket, length, timeout) do
    case tcp_recv(socket, length, timeout) do
      {:error, {:recv_failed, :timeout}} -> {:error, :pdu_read_timeout}
      other -> other
    end
  end

  # A peer max of 0 means unlimited
  defp max_fragment_size(%__MODULE__{max_pdu_length: max})
       when is_integer(max) and max > @pdv_overhead,
       do: max - @pdv_overhead

  defp max_fragment_size(_assoc), do: :infinity

  defp fragments(data, size) when size == :infinity or byte_size(data) <= size,
    do: [{data, true}]

  defp fragments(data, size) do
    <<fragment::binary-size(size), rest::binary>> = data
    [{fragment, false} | fragments(rest, size)]
  end

  defp receive_associate_response(socket, timeout) do
    with {:ok, header_bytes} <- tcp_recv(socket, @pdu_header_size, timeout),
         {:ok, _type, length} <- PDU.decode_header(header_bytes),
         {:ok, payload} <- tcp_recv(socket, length, timeout) do
      case PDU.decode_pdu(header_bytes <> payload) do
        {:ok, {:associate_ac, result}, _rest} ->
          {:ok, result}

        {:ok, {:associate_rj, %{result: result, reason: reason}}, _rest} ->
          {:error, {:association_rejected, result, reason}}

        {:ok, {:abort, %{source: source, reason: reason}}, _rest} ->
          {:error, {:association_aborted, source, reason}}

        {:ok, other, _rest} ->
          {:error, {:unexpected_pdu, other}}

        {:error, _} = error ->
          error
      end
    end
  end

  defp tcp_send(socket, data) do
    case :gen_tcp.send(socket, data) do
      :ok -> :ok
      {:error, reason} -> {:error, {:send_failed, reason}}
    end
  end

  defp tcp_recv(socket, length, timeout) do
    case :gen_tcp.recv(socket, length, timeout) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:recv_failed, reason}}
    end
  end
end
