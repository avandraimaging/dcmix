defmodule Dcmix.Network.CStore do
  @moduledoc """
  High-level DICOM C-STORE SCU operation.

  Sends a single DICOM SOP instance to a remote Service Class Provider.
  The instance is read from a DICOM Part 10 file, the SOP Class UID and
  SOP Instance UID are extracted from the dataset, and the file's own
  transfer syntax is proposed during association negotiation. After the
  remote accepts, the command and dataset are sent as separate PDVs and
  the response status is returned.

  ## Usage

      {:ok, 0x0000} =
        Dcmix.Network.CStore.send("localhost:104", "/path/to/study.dcm",
          calling_ae_title: "MY_SCU",
          called_ae_title: "PACS_AE"
        )
  """

  require Logger

  alias Dcmix.{DataSet, Parser}
  alias Dcmix.Network.{Association, DIMSE}
  alias Dcmix.Parser.TransferSyntax
  alias Dcmix.Writer

  # SOP Class UID and SOP Instance UID live in the dataset (group 0008).
  @sop_class_uid_tag {0x0008, 0x0016}
  @sop_instance_uid_tag {0x0008, 0x0018}

  @doc """
  Sends a single DICOM file to a remote SCP via C-STORE.

  ## Parameters

  - `addr` - Server address as `"host:port"`
  - `file_path` - Path to a DICOM Part 10 file to send
  - `opts` - Connection options:
    - `:calling_ae_title` - Calling AE Title (default: `"DCMIX"`)
    - `:called_ae_title` - Called AE Title (default: `"ANY-SCP"`)
    - `:verbose` - Enable verbose logging (default: `false`)
    - `:timeout` - TCP timeout in ms (default: 30000)
    - `:message_id` - Message ID for the C-STORE-RQ (default: 1)

  ## Returns

  - `{:ok, status}` where `status` is the DIMSE status code returned by
    the SCP (`0x0000` for success, non-zero for failure or warning)
  - `{:error, reason}` on local failures (file unreadable, association
    rejected, transport error, missing required UIDs)

  ## Examples

      {:ok, status} =
        Dcmix.Network.CStore.send("localhost:104", "ct_image.dcm",
          calling_ae_title: "MY_SCU",
          called_ae_title: "ORTHANC"
        )

      0x0000 = status
  """
  @spec send(String.t(), Path.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def send(addr, file_path, opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)
    calling_ae = Keyword.get(opts, :calling_ae_title, "DCMIX")
    called_ae = Keyword.get(opts, :called_ae_title, "ANY-SCP")
    timeout = Keyword.get(opts, :timeout, 30_000)
    message_id = Keyword.get(opts, :message_id, 1)

    with {:ok, dataset, ts_uid} <- read_file(file_path),
         {:ok, sop_class_uid} <- read_uid(dataset, @sop_class_uid_tag, :sop_class_uid),
         {:ok, sop_instance_uid} <-
           read_uid(dataset, @sop_instance_uid_tag, :sop_instance_uid) do
      request = %{
        sop_class_uid: sop_class_uid,
        sop_instance_uid: sop_instance_uid,
        dataset: dataset,
        transfer_syntax_uid: ts_uid,
        message_id: message_id,
        verbose: verbose,
        timeout: timeout
      }

      log_verbose(
        verbose,
        "Storing #{sop_instance_uid} (#{sop_class_uid}) in TS #{ts_uid}"
      )

      with {:ok, assoc} <-
             establish_association(addr, calling_ae, called_ae, sop_class_uid, ts_uid, timeout) do
        log_verbose(verbose, "Association established")
        run_cstore(assoc, request)
      end
    end
  end

  # ===========================================================================
  # Private implementation
  # ===========================================================================

  defp run_cstore(assoc, request) do
    with {:ok, pc} <- Association.accepted_context(assoc) do
      log_verbose(request.verbose, "Presentation context accepted (TS: #{pc.transfer_syntax})")
      execute_cstore(assoc, pc, request)
    end
  after
    Association.release(assoc)
  end

  defp execute_cstore(assoc, pc, request) do
    with :ok <- send_command(assoc, pc, request),
         :ok <- send_dataset(assoc, pc, request.dataset),
         _ <- log_verbose(request.verbose, "C-STORE-RQ sent, awaiting response..."),
         {:ok, status} <- receive_response(assoc, request.timeout) do
      log_verbose(request.verbose, "C-STORE complete (status=0x#{format_status(status)})")
      {:ok, status}
    end
  end

  defp send_command(assoc, pc, request) do
    command_bytes =
      DIMSE.build_cstore_rq(request.sop_class_uid, request.sop_instance_uid, request.message_id)

    Association.send_pdata(assoc, pc.id, true, command_bytes)
  end

  defp send_dataset(assoc, pc, dataset) do
    data_bytes = encode_dataset(dataset, pc.transfer_syntax)
    Association.send_pdata(assoc, pc.id, false, data_bytes)
  end

  defp receive_response(assoc, timeout) do
    case Association.receive_pdu(assoc, timeout) do
      {:ok, {:p_data, pdvs}} ->
        parse_response_pdvs(pdvs)

      {:ok, {:abort, _}} ->
        {:error, :association_aborted}

      {:ok, :release_rq} ->
        {:error, :unexpected_release}

      {:error, _} = error ->
        error
    end
  end

  defp parse_response_pdvs(pdvs) do
    case Enum.find(pdvs, & &1.is_command) do
      nil -> {:error, :missing_command_in_response}
      %{data: command_data} -> DIMSE.parse_status(command_data)
    end
  end

  defp establish_association(addr, calling_ae, called_ae, sop_class_uid, ts_uid, timeout) do
    Association.request(addr,
      calling_ae_title: calling_ae,
      called_ae_title: called_ae,
      abstract_syntaxes: [sop_class_uid],
      transfer_syntaxes: [ts_uid],
      timeout: timeout
    )
  end

  defp read_file(file_path) do
    with {:ok, ts_uid} <- Parser.get_transfer_syntax(file_path),
         {:ok, dataset} <- Parser.parse_file(file_path) do
      {:ok, dataset, ts_uid}
    end
  end

  defp read_uid(dataset, tag, name) do
    case DataSet.get_string(dataset, tag) do
      nil -> {:error, {:missing_uid, name}}
      "" -> {:error, {:missing_uid, name}}
      uid -> {:ok, String.trim_trailing(uid, <<0>>)}
    end
  end

  defp encode_dataset(dataset, transfer_syntax_uid) do
    {:ok, ts} = TransferSyntax.lookup(transfer_syntax_uid)
    {_file_meta, data_only} = DataSet.split_file_meta(dataset)

    if ts.explicit_vr do
      Writer.ExplicitVR.encode(data_only, big_endian: ts.big_endian)
    else
      Writer.ImplicitVR.encode(data_only)
    end
  end

  defp format_status(status) do
    status
    |> Integer.to_string(16)
    |> String.pad_leading(4, "0")
  end

  defp log_verbose(true, message), do: Logger.info("[CStore] #{message}")
  defp log_verbose(false, _message), do: :ok
end
