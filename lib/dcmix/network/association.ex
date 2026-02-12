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
          presentation_contexts: [PDU.accepted_context()]
        }

  defstruct [:socket, :max_pdu_length, presentation_contexts: []]

  # Default TCP recv timeout (30 seconds)
  @default_timeout 30_000

  # PDU header size
  @pdu_header_size 6

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
    - `:timeout` - TCP timeout in ms (default: 30000)
    - `:max_pdu_length` - Max PDU length to propose (default: 16384)

  ## Returns
  - `{:ok, association}` on successful negotiation
  - `{:error, reason}` on failure
  """
  @spec request(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def request(addr, opts \\ []) do
    calling_ae = Keyword.get(opts, :calling_ae_title, "DCMIX")
    called_ae = Keyword.get(opts, :called_ae_title, "ANY-SCP")

    abstract_syntaxes =
      Keyword.get(opts, :abstract_syntaxes, [@study_root_qr_find])

    transfer_syntaxes =
      Keyword.get(opts, :transfer_syntaxes, [
        TransferSyntax.implicit_vr_little_endian(),
        TransferSyntax.explicit_vr_little_endian()
      ])

    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_pdu_length = Keyword.get(opts, :max_pdu_length, 16_384)

    with {:ok, {host, port}} <- parse_address(addr),
         {:ok, socket} <- connect(host, port, timeout),
         :ok <-
           send_associate_rq(
             socket,
             calling_ae,
             called_ae,
             abstract_syntaxes,
             transfer_syntaxes,
             max_pdu_length
           ),
         {:ok, result} <- receive_associate_response(socket, timeout) do
      {:ok,
       %__MODULE__{
         socket: socket,
         max_pdu_length: result.max_pdu_length,
         presentation_contexts: result.presentation_contexts
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
  Sends a P-DATA PDU with the given data.
  """
  @spec send_pdata(t(), non_neg_integer(), boolean(), binary()) :: :ok | {:error, term()}
  def send_pdata(%__MODULE__{socket: socket}, context_id, is_command, data) do
    pdu = PDU.encode_p_data(context_id, is_command, true, data)
    tcp_send(socket, pdu)
  end

  @doc """
  Receives and decodes the next PDU from the remote peer.
  """
  @spec receive_pdu(t(), non_neg_integer()) :: {:ok, PDU.pdu()} | {:error, term()}
  def receive_pdu(%__MODULE__{socket: socket}, timeout \\ @default_timeout) do
    with {:ok, header_bytes} <- tcp_recv(socket, @pdu_header_size, timeout),
         {:ok, _type, length} <- PDU.decode_header(header_bytes),
         {:ok, payload} <- tcp_recv(socket, length, timeout) do
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

  defp send_associate_rq(
         socket,
         calling_ae,
         called_ae,
         abstract_syntaxes,
         transfer_syntaxes,
         max_pdu_length
       ) do
    presentation_contexts =
      abstract_syntaxes
      |> Enum.with_index(1)
      |> Enum.map(fn {abstract_syntax, idx} ->
        # Presentation context IDs must be odd numbers
        pc_id = idx * 2 - 1

        %{
          id: pc_id,
          abstract_syntax: abstract_syntax,
          transfer_syntaxes: transfer_syntaxes
        }
      end)

    pdu =
      PDU.encode_associate_rq(calling_ae, called_ae, presentation_contexts,
        max_pdu_length: max_pdu_length
      )

    tcp_send(socket, pdu)
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
