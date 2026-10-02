defmodule Dcmix.Network.CGet do
  @moduledoc """
  High-level DICOM C-GET SCU operation.

  Retrieves instances matching a query identifier over a single association,
  modelled on dcmtk's `getscu` / `DcmSCU::sendCGETRequest`. The remote SCP
  sends each instance back as a C-STORE sub-operation on the same association,
  so the association proposes one storage presentation context per SOP class
  with the SCP role (SCP/SCU Role Selection, PS3.7 D.3.3.4) alongside the
  Q/R GET context.

  ## Storage

  In `:bit_preserving` mode (the default) each instance is written to
  `:output_directory` as a Part 10 file exactly as received: the File Meta
  Information is generated from the C-STORE-RQ and the accepted transfer
  syntax, and data set fragments are appended to the file as they arrive, so
  an instance is never held in memory whole. Files are named by the sanitized
  Affected SOP Instance UID, with no extension, as dcmtk does. Each instance is
  written to a temporary `<name>.part` file and renamed once complete, so an
  existing file of the same name is replaced only by a whole instance.

  In `:ignore` mode instances are received and discarded, and each
  sub-operation is still answered with success.

  ## Timeouts

  `:timeout` applies to every network read. If the SCP goes quiet for that
  long during the retrieve, a C-CANCEL-RQ is sent and the final C-GET-RSP is
  awaited for at most five more seconds. Either way the call returns
  `{:error, {:timeout, result}}`, where `result` holds the files received so
  far and, if the SCP answered the cancel, its final status. The association
  is released when the SCP answered and aborted otherwise.
  """

  require Logger

  alias Dcmix.DataSet
  alias Dcmix.Network.{Association, DIMSE, StorageSOPClasses}
  alias Dcmix.Parser.TransferSyntax
  alias Dcmix.Writer

  defmodule Result do
    @moduledoc """
    Outcome of a C-GET.

    `status` is the status of the final C-GET-RSP. The sub-operation counts
    are those last reported by the SCP. `files` lists the paths written, each
    once, in the order first received (empty in `:ignore` mode).
    """

    @type t :: %__MODULE__{
            status: non_neg_integer() | nil,
            completed: non_neg_integer(),
            failed: non_neg_integer(),
            warning: non_neg_integer(),
            files: [Path.t()]
          }

    defstruct status: nil, completed: 0, failed: 0, warning: 0, files: []
  end

  @patient_root_qr_get "1.2.840.10008.5.1.4.1.2.1.3"
  @study_root_qr_get "1.2.840.10008.5.1.4.1.2.2.3"

  @cstore_rq 0x0001
  @cget_rsp 0x8010

  @status_success 0x0000
  @status_sop_class_not_supported 0x0122
  @status_out_of_resources 0xA700
  @status_cannot_understand 0xC000

  @max_presentation_contexts 128
  @cancel_wait 5_000
  @message_id 1

  @doc """
  Performs a C-GET against a DICOM server.

  ## Parameters

  - `addr` - Server address as `"host:port"`
  - `query_dataset` - A `Dcmix.DataSet` holding the retrieve identifier
    (Query/Retrieve Level plus the unique keys)
  - `opts` - Options:
    - `:calling_ae_title` - Calling AE Title (default: `"DCMIX"`)
    - `:called_ae_title` - Called AE Title (default: `"ANY-SCP"`)
    - `:timeout` - TCP timeout in ms (default: 30000)
    - `:verbose` - Enable verbose logging (default: `false`)
    - `:query_model` - `:patient_root` (default) or `:study_root`
    - `:output_directory` - Where files are written (default: `"."`,
      created if missing)
    - `:storage_mode` - `:bit_preserving` (default) or `:ignore`
    - `:storage_sop_classes` - Storage SOP Classes to accept (default:
      `Dcmix.Network.StorageSOPClasses.uids/0`, at most 127)
    - `:storage_transfer_syntaxes` - Transfer syntaxes proposed for each
      storage context (default: Explicit VR LE, Implicit VR LE, Explicit
      VR BE). Data sets are stored without being parsed, so any syntax may
      be listed.
    - `:max_pdu_length` - Max PDU length to propose (default: 16384)

  ## Returns

  - `{:ok, %Dcmix.Network.CGet.Result{}}` when the SCP sent a final
    C-GET-RSP, whatever its status (success, warning, failure or cancel)
  - `{:error, {:timeout, %Dcmix.Network.CGet.Result{}}}` on a read timeout
    (see the module docs)
  - `{:error, reason}` on connection, association or protocol failure

  ## Examples

      query =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0008, 0x0052}, :CS, "STUDY")
        |> Dcmix.DataSet.put_element({0x0020, 0x000D}, :UI, "1.2.3.4")

      {:ok, result} =
        Dcmix.Network.CGet.get("localhost:4242", query,
          called_ae_title: "PACS_AE",
          query_model: :study_root,
          output_directory: "retrieved"
        )
  """
  @spec get(String.t(), DataSet.t(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def get(addr, %DataSet{} = query_dataset, opts \\ []) do
    config = %{
      calling_ae: Keyword.get(opts, :calling_ae_title, "DCMIX"),
      called_ae: Keyword.get(opts, :called_ae_title, "ANY-SCP"),
      timeout: Keyword.get(opts, :timeout, 30_000),
      verbose: Keyword.get(opts, :verbose, false),
      output_directory: Keyword.get(opts, :output_directory, "."),
      storage_mode: Keyword.get(opts, :storage_mode, :bit_preserving),
      storage_sop_classes: Keyword.get(opts, :storage_sop_classes, StorageSOPClasses.uids()),
      storage_transfer_syntaxes:
        Keyword.get(opts, :storage_transfer_syntaxes, [
          TransferSyntax.explicit_vr_little_endian(),
          TransferSyntax.implicit_vr_little_endian(),
          TransferSyntax.explicit_vr_big_endian()
        ]),
      max_pdu_length: Keyword.get(opts, :max_pdu_length, 16_384)
    }

    with {:ok, get_uid} <- query_model_uid(Keyword.get(opts, :query_model, :patient_root)),
         :ok <- check_storage_mode(config.storage_mode),
         :ok <- check_context_count(config.storage_sop_classes),
         :ok <- prepare_output_directory(config),
         {:ok, assoc} <- Association.request(addr, association_opts(get_uid, config)) do
      log_verbose(config, "Association established")
      run_cget(assoc, get_uid, query_dataset, config)
    end
  end

  # ===========================================================================
  # Setup
  # ===========================================================================

  defp query_model_uid(:patient_root), do: {:ok, @patient_root_qr_get}
  defp query_model_uid(:study_root), do: {:ok, @study_root_qr_get}
  defp query_model_uid(other), do: {:error, {:invalid_query_model, other}}

  defp check_storage_mode(mode) when mode in [:bit_preserving, :ignore], do: :ok
  defp check_storage_mode(mode), do: {:error, {:invalid_storage_mode, mode}}

  # One context per storage class plus the GET context
  defp check_context_count(storage_sop_classes) do
    count = length(storage_sop_classes) + 1

    if count <= @max_presentation_contexts,
      do: :ok,
      else: {:error, {:too_many_presentation_contexts, count}}
  end

  defp prepare_output_directory(%{storage_mode: :ignore}), do: :ok

  defp prepare_output_directory(%{output_directory: dir}) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:output_directory_error, reason}}
    end
  end

  defp association_opts(get_uid, config) do
    get_context = %{
      abstract_syntax: get_uid,
      transfer_syntaxes: [
        TransferSyntax.explicit_vr_little_endian(),
        TransferSyntax.implicit_vr_little_endian()
      ]
    }

    storage_contexts =
      Enum.map(config.storage_sop_classes, fn uid ->
        %{
          abstract_syntax: uid,
          transfer_syntaxes: config.storage_transfer_syntaxes,
          scu_role: false,
          scp_role: true
        }
      end)

    [
      calling_ae_title: config.calling_ae,
      called_ae_title: config.called_ae,
      presentation_contexts: [get_context | storage_contexts],
      timeout: config.timeout,
      max_pdu_length: config.max_pdu_length
    ]
  end

  # ===========================================================================
  # Request / response loop
  # ===========================================================================

  defp run_cget(assoc, get_uid, query_dataset, config) do
    with {:ok, pc} <- Association.accepted_context(assoc, get_uid),
         :ok <- send_request(assoc, pc, get_uid, query_dataset) do
      log_verbose(config, "C-GET request sent (TS: #{pc.transfer_syntax})")
      storage_contexts = storage_contexts(assoc, get_uid)
      warn_without_scp_role(storage_contexts)

      %{
        assoc: assoc,
        config: config,
        get_context_id: pc.id,
        storage_contexts: storage_contexts,
        timeout: config.timeout,
        cancelled: false,
        command: <<>>,
        incoming: nil,
        result: %Result{}
      }
      |> receive_loop()
      |> finish()
    else
      error ->
        Association.release(assoc)
        error
    end
  end

  defp storage_contexts(assoc, get_uid) do
    assoc.presentation_contexts
    |> Enum.filter(&(&1.result == 0 and &1.abstract_syntax != get_uid))
    |> Map.new(&{&1.id, &1})
  end

  # Without the SCP role the peer is not supposed to send us C-STOREs, so its
  # sub-operations will most likely fail on its side
  defp warn_without_scp_role(storage_contexts) do
    unless Enum.any?(storage_contexts, fn {_id, pc} -> pc[:scp_role] == true end) do
      Logger.warning(
        "[CGet] SCP accepted the SCP role for no storage context; " <>
          "C-GET sub-operations will likely fail on the SCP"
      )
    end
  end

  defp send_request(assoc, pc, get_uid, query_dataset) do
    with :ok <-
           Association.send_pdata(assoc, pc.id, true, DIMSE.build_cget_rq(get_uid, @message_id)) do
      Association.send_pdata(
        assoc,
        pc.id,
        false,
        encode_dataset(query_dataset, pc.transfer_syntax)
      )
    end
  end

  defp finish({:done, %{cancelled: false} = state}) do
    Association.release(state.assoc)
    {:ok, final_result(state)}
  end

  defp finish({:done, state}) do
    Association.release(state.assoc)
    {:error, {:timeout, final_result(state)}}
  end

  defp finish({:timed_out, state}) do
    discard_partial(state)
    Association.abort(state.assoc)
    {:error, {:timeout, final_result(state)}}
  end

  defp finish({:error, reason, state}) do
    discard_partial(state)
    Association.abort(state.assoc)
    {:error, reason}
  end

  defp final_result(%{result: result}), do: %{result | files: Enum.reverse(result.files)}

  defp receive_loop(state) do
    case Association.receive_pdu(state.assoc, state.timeout) do
      {:ok, {:p_data, pdvs}} ->
        case handle_pdvs(pdvs, state) do
          {:cont, state} -> receive_loop(state)
          other -> other
        end

      {:ok, {:abort, _}} ->
        {:error, :association_aborted, state}

      {:ok, :release_rq} ->
        {:error, :unexpected_release, state}

      {:ok, other} ->
        {:error, {:unexpected_pdu, other}, state}

      {:error, {:recv_failed, :timeout}} ->
        handle_timeout(state)

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp handle_timeout(%{cancelled: true} = state), do: {:timed_out, state}

  defp handle_timeout(state) do
    log_verbose(state.config, "No response within timeout, sending C-CANCEL-RQ")
    cancel = DIMSE.build_ccancel_rq(@message_id)

    case Association.send_pdata(state.assoc, state.get_context_id, true, cancel) do
      :ok -> receive_loop(%{state | cancelled: true, timeout: min(state.timeout, @cancel_wait)})
      {:error, reason} -> {:error, reason, state}
    end
  end

  # A P-DATA PDU may mix command and data PDVs, and a command or data set may
  # span several PDUs, so PDVs are handled one at a time.
  defp handle_pdvs([], state), do: {:cont, state}

  defp handle_pdvs([pdv | rest], state) do
    case handle_pdv(pdv, state) do
      {:cont, state} -> handle_pdvs(rest, state)
      other -> other
    end
  end

  defp handle_pdv(%{is_command: true}, %{incoming: incoming} = state) when incoming != nil,
    do: {:error, :unexpected_command_fragment, state}

  defp handle_pdv(%{is_command: true, is_last: false, data: data}, state),
    do: {:cont, %{state | command: state.command <> data}}

  defp handle_pdv(%{is_command: true} = pdv, state) do
    case DIMSE.decode_command(state.command <> pdv.data) do
      {:ok, command} -> handle_command(command, pdv.context_id, %{state | command: <<>>})
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp handle_pdv(_data_pdv, %{incoming: nil} = state),
    do: {:error, :unexpected_data_fragment, state}

  defp handle_pdv(%{context_id: id}, %{incoming: %{context_id: expected}} = state)
       when id != expected,
       do: {:error, {:unexpected_data_context, id}, state}

  defp handle_pdv(pdv, state) do
    state = %{state | incoming: write_fragment(state.incoming, pdv.data)}
    if pdv.is_last, do: complete_incoming(state), else: {:cont, state}
  end

  defp handle_command(%{command_field: @cget_rsp} = command, context_id, state) do
    final = not DIMSE.status_pending?(command.status)
    state = %{state | result: update_result(state.result, command, final)}
    log_verbose(state.config, "C-GET-RSP status 0x#{hex(command.status)}")

    cond do
      DIMSE.dataset_present?(command.command_data_set_type) ->
        {:cont,
         %{state | incoming: %{kind: :get_identifier, context_id: context_id, final: final}}}

      final ->
        {:done, state}

      true ->
        {:cont, state}
    end
  end

  defp handle_command(%{command_field: @cstore_rq} = command, context_id, state) do
    log_verbose(state.config, "C-STORE-RQ #{command.affected_sop_instance_uid}")

    if DIMSE.dataset_present?(command.command_data_set_type) do
      {:cont, %{state | incoming: start_store(command, context_id, state)}}
    else
      # Nothing will follow, so answer now rather than wait for a data set
      store = %{
        kind: :discard,
        command: command,
        context_id: context_id,
        status: @status_cannot_understand
      }

      complete_incoming(%{state | incoming: store})
    end
  end

  defp handle_command(%{command_field: field}, _context_id, state),
    do: {:error, {:unexpected_command, field}, state}

  defp update_result(result, command, final) do
    %{
      result
      | status: if(final, do: command.status, else: result.status),
        completed: command.completed || result.completed,
        failed: command.failed || result.failed,
        warning: command.warning || result.warning
    }
  end

  # ===========================================================================
  # C-STORE sub-operations
  # ===========================================================================

  defp start_store(command, context_id, state) do
    store = %{kind: :discard, command: command, context_id: context_id, status: @status_success}

    case Map.fetch(state.storage_contexts, context_id) do
      :error ->
        # dcmtk rejects these as DIMSE_NOVALIDPRESENTATIONCONTEXTID
        %{store | status: @status_sop_class_not_supported}

      {:ok, _pc} when state.config.storage_mode == :ignore ->
        store

      {:ok, pc} ->
        open_store_file(store, pc, state.config)
    end
  end

  defp open_store_file(store, pc, config) do
    with {:ok, name} <- storage_filename(store.command.affected_sop_instance_uid),
         path = Path.join(config.output_directory, name),
         part_path = path <> ".part",
         {:ok, io} <- File.open(part_path, [:write, :binary, :raw]) do
      store
      |> Map.merge(%{kind: :file, io: io, path: path, part_path: part_path})
      |> write_fragment(file_meta_header(store.command, pc, config))
    else
      {:error, :invalid_filename} -> %{store | status: @status_cannot_understand}
      {:error, _reason} -> %{store | status: @status_out_of_resources}
    end
  end

  defp file_meta_header(command, pc, config) do
    Writer.file_meta_header(
      command.affected_sop_class_uid || "",
      command.affected_sop_instance_uid || "",
      pc.transfer_syntax,
      source_ae_title: config.calling_ae
    )
  end

  defp write_fragment(%{kind: :file} = store, data) do
    case :file.write(store.io, data) do
      :ok ->
        store

      {:error, _reason} ->
        close_and_delete(store.io, store.part_path)
        %{store | kind: :discard, status: @status_out_of_resources}
    end
  end

  defp write_fragment(incoming, _data), do: incoming

  defp complete_incoming(%{incoming: %{kind: :get_identifier, final: final}} = state) do
    state = %{state | incoming: nil}
    if final, do: {:done, state}, else: {:cont, state}
  end

  defp complete_incoming(%{incoming: store} = state) do
    {status, state} = close_store(store, state)
    command = store.command

    rsp =
      DIMSE.build_cstore_rsp(
        command.affected_sop_class_uid || "",
        command.affected_sop_instance_uid || "",
        command.message_id || 0,
        status
      )

    state = %{state | incoming: nil}

    case Association.send_pdata(state.assoc, store.context_id, true, rsp) do
      :ok -> {:cont, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  # Only a complete .part file replaces the final name, so a failed repeat of
  # an instance never destroys a good earlier copy
  defp close_store(%{kind: :file} = store, state) do
    with :ok <- File.close(store.io),
         :ok <- File.rename(store.part_path, store.path) do
      {@status_success, %{state | result: add_file(state.result, store.path)}}
    else
      {:error, _reason} ->
        _ = File.rm(store.part_path)
        {@status_out_of_resources, state}
    end
  end

  defp close_store(store, state), do: {store.status, state}

  # files is kept newest-first and reversed at the end
  defp add_file(result, path) do
    if path in result.files, do: result, else: %{result | files: [path | result.files]}
  end

  defp discard_partial(%{incoming: %{kind: :file} = store}),
    do: close_and_delete(store.io, store.part_path)

  defp discard_partial(_state), do: :ok

  defp close_and_delete(io, path) do
    _ = File.close(io)
    _ = File.rm(path)
    :ok
  end

  # Mirrors DcmSCU's bit-preserving path (dcmnet/libsrc/scu.cc,
  # handleCGETSession): the file is named by the Affected SOP Instance UID
  # passed through OFStandard::sanitizeFilename(), with no modality prefix or
  # extension (those come from createStorageFilename(), used only when dcmtk
  # stores in memory first).
  #
  # Deliberately stricter than sanitizeFilename() for Windows hosts: ":" (NTFS
  # alternate data streams) and space are replaced, and names that are empty
  # or end in "." (which Windows strips; covers "." and "..") are refused.
  # Valid UIDs are only [0-9.] and never end in ".", so names still match
  # dcmtk's for them.
  defp storage_filename(uid) when is_binary(uid) do
    name =
      uid
      |> String.trim_trailing(<<0>>)
      |> String.trim()
      |> sanitize_filename()

    if name == "" or String.ends_with?(name, "."),
      do: {:error, :invalid_filename},
      else: {:ok, name}
  end

  defp storage_filename(_uid), do: {:error, :invalid_filename}

  # Letters, digits, "-", ".", "@", "_"
  defp sanitize_filename(name) do
    for <<c <- name>>, into: "", do: if(filename_char?(c), do: <<c>>, else: "_")
  end

  defp filename_char?(c) when c in ?0..?9 or c in ?a..?z or c in ?A..?Z, do: true
  defp filename_char?(c), do: c in ~c"-.@_"

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp encode_dataset(dataset, transfer_syntax_uid) do
    {:ok, ts} = TransferSyntax.lookup(transfer_syntax_uid)

    if ts.explicit_vr do
      Writer.ExplicitVR.encode(dataset, big_endian: ts.big_endian)
    else
      Writer.ImplicitVR.encode(dataset)
    end
  end

  defp hex(nil), do: "????"
  defp hex(value), do: value |> Integer.to_string(16) |> String.pad_leading(4, "0")

  defp log_verbose(%{verbose: true}, message), do: Logger.info("[CGet] #{message}")
  defp log_verbose(_config, _message), do: :ok
end
