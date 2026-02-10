defmodule Dcmix.Network.CFind do
  @moduledoc """
  High-level DICOM C-FIND SCU operation.

  Orchestrates a complete C-FIND query against a DICOM server:
  association negotiation, command/query encoding, response processing,
  and JSON result formatting.

  This module produces output compatible with the `DicomRustler.run_query/1`
  API, making it a drop-in replacement for mender's DICOM query needs.
  """

  require Logger

  alias Dcmix.Export.JSON
  alias Dcmix.Network.{Association, DIMSE, Query}
  alias Dcmix.Parser.{ExplicitVR, ImplicitVR, TransferSyntax}
  alias Dcmix.Writer

  # Study Root Query/Retrieve Information Model - FIND
  @study_root_qr_find "1.2.840.10008.5.1.4.1.2.2.1"

  @doc """
  Performs a C-FIND query against a DICOM server.

  ## Parameters

  - `opts` - Query options map:
    - `:addr` - Server address as `"host:port"` (required)
    - `:query` - List of query terms (required)
    - `:calling_ae_title` - Calling AE Title (default: `"DCMIX"`)
    - `:called_ae_title` - Called AE Title (default: `"ANY-SCP"`)
    - `:verbose` - Enable verbose logging (default: `false`)
    - `:timeout` - TCP timeout in ms (default: 30000)

  ## Returns

  - `{:ok, %{matches: count, matched: [json_strings]}}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, result} = Dcmix.Network.CFind.run(%{
        addr: "localhost:4242",
        query: ["PatientName", "StudyDate=20250101"],
        calling_ae_title: "MY_AE",
        called_ae_title: "PACS_AE"
      })
  """
  @spec run(map()) ::
          {:ok, %{matches: non_neg_integer(), matched: [String.t()]}} | {:error, term()}
  def run(%{addr: addr, query: query_terms} = opts) do
    verbose = Map.get(opts, :verbose, false)
    calling_ae = Map.get(opts, :calling_ae_title, "DCMIX")
    called_ae = Map.get(opts, :called_ae_title, "ANY-SCP")
    timeout = Map.get(opts, :timeout, 30_000)

    with {:ok, query_ds} <- Query.parse_terms(query_terms),
         _ <- log_verbose(verbose, "Query dataset built with #{Dcmix.DataSet.size(query_ds)} elements"),
         {:ok, assoc} <- establish_association(addr, calling_ae, called_ae, timeout),
         _ <- log_verbose(verbose, "Association established"),
         {:ok, pc} <- Association.accepted_context(assoc),
         _ <- log_verbose(verbose, "Presentation context accepted (TS: #{pc.transfer_syntax})") do
      result = execute_cfind(assoc, pc, query_ds, verbose, timeout)
      Association.release(assoc)
      result
    end
  end

  # ===========================================================================
  # Private implementation
  # ===========================================================================

  defp establish_association(addr, calling_ae, called_ae, timeout) do
    Association.request(addr,
      calling_ae_title: calling_ae,
      called_ae_title: called_ae,
      abstract_syntaxes: [@study_root_qr_find],
      transfer_syntaxes: [
        TransferSyntax.implicit_vr_little_endian(),
        TransferSyntax.explicit_vr_little_endian()
      ],
      timeout: timeout
    )
  end

  defp execute_cfind(assoc, pc, query_ds, verbose, timeout) do
    with :ok <- send_cfind_command(assoc, pc),
         :ok <- send_query_dataset(assoc, pc, query_ds),
         _ <- log_verbose(verbose, "C-FIND request sent, awaiting responses...") do
      receive_responses(assoc, pc, verbose, timeout, [])
    end
  end

  defp send_cfind_command(assoc, pc) do
    command_bytes = DIMSE.build_cfind_rq(@study_root_qr_find, 1)
    Association.send_pdata(assoc, pc.id, true, command_bytes)
  end

  defp send_query_dataset(assoc, pc, query_ds) do
    query_bytes = encode_dataset(query_ds, pc.transfer_syntax)
    Association.send_pdata(assoc, pc.id, false, query_bytes)
  end

  defp receive_responses(assoc, pc, verbose, timeout, acc) do
    case Association.receive_pdu(assoc, timeout) do
      {:ok, {:p_data, pdvs}} ->
        handle_response(assoc, pc, verbose, timeout, acc, pdvs)

      {:ok, {:abort, _}} ->
        {:error, :association_aborted}

      {:ok, :release_rq} ->
        {:error, :unexpected_release}

      {:error, _} = error ->
        error
    end
  end

  defp handle_response(assoc, pc, verbose, timeout, acc, pdvs) do
    # Find the command PDV
    command_pdv = Enum.find(pdvs, & &1.is_command)
    data_pdv = Enum.find(pdvs, &(not &1.is_command))

    case command_pdv do
      nil ->
        {:error, :missing_command_in_response}

      %{data: command_data} ->
        case DIMSE.parse_status(command_data) do
          {:ok, status} ->
            handle_status(assoc, pc, verbose, timeout, acc, status, data_pdv)

          {:error, _} = error ->
            error
        end
    end
  end

  defp handle_status(_assoc, _pc, verbose, _timeout, acc, status, _data_pdv)
       when status == 0x0000 do
    count = length(acc)
    log_verbose(verbose, "C-FIND complete: #{count} matches")
    {:ok, %{matches: count, matched: Enum.reverse(acc)}}
  end

  defp handle_status(assoc, pc, verbose, timeout, acc, status, data_pdv)
       when status in [0xFF00, 0xFF01] do
    # Pending — get the data dataset and convert to JSON
    case get_response_data(assoc, pc, data_pdv, timeout) do
      {:ok, json_string} ->
        log_verbose(verbose, "Match ##{length(acc) + 1}")
        receive_responses(assoc, pc, verbose, timeout, [json_string | acc])

      {:error, reason} ->
        Logger.warning("Failed to decode response data: #{inspect(reason)}, using empty JSON")
        receive_responses(assoc, pc, verbose, timeout, ["{}" | acc])
    end
  end

  defp handle_status(_assoc, _pc, _verbose, _timeout, _acc, status, _data_pdv) do
    {:error, {:cfind_failed, status}}
  end

  defp get_response_data(assoc, pc, data_pdv, timeout) do
    data_bytes = extract_data_bytes(assoc, data_pdv, timeout)

    case data_bytes do
      {:ok, bytes} -> dataset_to_json(bytes, pc.transfer_syntax)
      {:error, _} = error -> error
    end
  end

  # Data may come in the same P-DATA PDU as the command (second PDV),
  # or in a separate P-DATA PDU.
  defp extract_data_bytes(_assoc, %{data: data}, _timeout)
       when is_binary(data) and byte_size(data) > 0 do
    {:ok, data}
  end

  defp extract_data_bytes(assoc, _nil_or_empty, timeout) do
    case Association.receive_pdu(assoc, timeout) do
      {:ok, {:p_data, pdvs}} ->
        data =
          pdvs
          |> Enum.reject(& &1.is_command)
          |> Enum.map(& &1.data)
          |> IO.iodata_to_binary()

        {:ok, data}

      {:error, _} = error ->
        error
    end
  end

  defp dataset_to_json(data_bytes, transfer_syntax_uid) do
    {:ok, ts} = TransferSyntax.lookup(transfer_syntax_uid)

    parse_result =
      if ts.explicit_vr do
        ExplicitVR.parse(data_bytes, big_endian: ts.big_endian)
      else
        ImplicitVR.parse(data_bytes)
      end

    case parse_result do
      {:ok, dataset, _rest} ->
        JSON.encode(dataset)

      {:error, _} = error ->
        error
    end
  end

  defp encode_dataset(dataset, transfer_syntax_uid) do
    {:ok, ts} = TransferSyntax.lookup(transfer_syntax_uid)

    if ts.explicit_vr do
      Writer.ExplicitVR.encode(dataset, big_endian: ts.big_endian)
    else
      Writer.ImplicitVR.encode(dataset)
    end
  end

  defp log_verbose(true, message), do: Logger.info("[CFind] #{message}")
  defp log_verbose(false, _message), do: :ok
end
