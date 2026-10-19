defmodule Dcmix.Network.SCP do
  @moduledoc """
  Serves one association accepted on a TCP socket, as an SCP.

  `serve/2` reads the A-ASSOCIATE-RQ, answers it with an A-ASSOCIATE-AC or
  -RJ (see `Dcmix.Network.Negotiation`), then answers DIMSE requests until
  the requestor releases or aborts the association:

  - C-ECHO, on the Verification SOP Class, is always answered with success.
  - C-STORE, on the Storage SOP Classes, when given a handler (see
    `Dcmix.Network.SCP.Handler`): each instance is written to a file in the
    storage directory as it arrives, then handed to the handler, whose status
    is sent in the C-STORE-RSP.

  It runs in the calling process and uses the socket in passive mode.
  `Dcmix.Network.Listener` calls it for each connection it accepts.
  """

  require Logger

  alias Dcmix.{DataSet, Tag}

  alias Dcmix.Network.{
    Association,
    DIMSE,
    InstanceFile,
    Negotiation,
    PDU,
    SOPClassUID,
    StorageSOPClasses
  }

  alias Dcmix.Parser.TransferSyntax

  require Dcmix.Network.DIMSE.CommandField, as: CommandField
  require Dcmix.Network.DIMSE.Status, as: Status
  require Dcmix.Network.PDU.PresentationContextResult, as: ContextResult

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
  - `:handler` - `{module, arg}` implementing `Dcmix.Network.SCP.Handler`;
    with it, the Storage SOP Classes are accepted as well as Verification
  - `:storage_directory` - where instances are written (required with
    `:handler`)
  - `:storage_sop_classes` - Storage SOP Classes accepted (default:
    `Dcmix.Network.StorageSOPClasses.uids/0`)
  - `:storage_transfer_syntaxes` - transfer syntaxes accepted for them,
    compressed ones included, taken as sent (default: every transfer syntax
    in `Dcmix.Parser.TransferSyntax.all/0`)

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
        abstract_syntaxes: abstract_syntaxes(opts)
      )
      |> answer(socket, rq, max_pdu_length, timeout, opts)
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

  # Abstract syntaxes we accept, each with the transfer syntaxes we accept for
  # it. Verification is always accepted; the Storage SOP Classes only when
  # there is a handler for what they store.
  defp abstract_syntaxes(opts) do
    verification = %{
      SOPClassUID.verification() => [
        TransferSyntax.explicit_vr_little_endian(),
        TransferSyntax.implicit_vr_little_endian()
      ]
    }

    if Keyword.has_key?(opts, :handler),
      do: Map.merge(storage_abstract_syntaxes(opts), verification),
      else: verification
  end

  defp storage_abstract_syntaxes(opts) do
    transfer_syntaxes =
      Keyword.get_lazy(opts, :storage_transfer_syntaxes, fn ->
        Enum.map(TransferSyntax.all(), & &1.uid)
      end)

    opts
    |> Keyword.get(:storage_sop_classes, StorageSOPClasses.uids())
    |> Map.new(&{&1, transfer_syntaxes})
  end

  # ===========================================================================
  # Association establishment
  # ===========================================================================

  defp receive_associate_rq(socket, timeout) do
    case Association.receive_pdu(%Association{socket: socket}, timeout) do
      {:ok, {:associate_rq, rq}} ->
        {:ok, rq}

      {:ok, other} ->
        Association.abort(%Association{socket: socket})
        {:error, {:unexpected_pdu, other}}

      {:error, reason} = error ->
        close_after_error(%Association{socket: socket}, reason)
        error
    end
  end

  defp answer({:reject, rejection}, socket, rq, _max_pdu_length, _timeout, _opts),
    do: reject(socket, rq, rejection)

  defp answer({:accept, contexts}, socket, rq, max_pdu_length, timeout, opts) do
    pdu = PDU.encode_associate_ac(rq, contexts, max_pdu_length: max_pdu_length)

    assoc = %Association{
      socket: socket,
      max_pdu_length: rq.max_pdu_length,
      local_max_pdu_length: max_pdu_length,
      presentation_contexts: Enum.filter(contexts, &(&1.result == ContextResult.acceptance()))
    }

    case :gen_tcp.send(socket, pdu) do
      :ok -> serve_dimse(new_state(assoc, rq, timeout, opts))
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

  # `command` collects the PDVs of a command that spans several of them;
  # `incoming` is the C-STORE whose data set is arriving
  defp new_state(assoc, rq, timeout, opts) do
    %{
      assoc: assoc,
      timeout: timeout,
      calling_ae_title: rq.calling_ae_title,
      storage_directory: Keyword.get(opts, :storage_directory),
      handler: init_handler(Keyword.get(opts, :handler), assoc, rq),
      command: [],
      incoming: nil
    }
  end

  defp init_handler(nil, _assoc, _rq), do: nil

  defp init_handler({module, arg}, assoc, rq) do
    association = %{
      calling_ae_title: rq.calling_ae_title,
      called_ae_title: rq.called_ae_title,
      peer: peer(assoc.socket)
    }

    Code.ensure_loaded(module)

    if function_exported?(module, :init, 2) do
      {:ok, handler_state} = module.init(association, arg)
      {module, handler_state}
    else
      {module, arg}
    end
  end

  defp peer(socket) do
    case :inet.peername(socket) do
      {:ok, peer} -> peer
      {:error, _reason} -> nil
    end
  end

  defp serve_dimse(state) do
    case Association.receive_pdu(state.assoc, state.timeout) do
      {:ok, {:p_data, pdvs}} ->
        handle_pdvs(state, pdvs)

      {:ok, :release_rq} when state.incoming == nil ->
        _ = :gen_tcp.send(state.assoc.socket, PDU.encode_release_rp())
        :gen_tcp.close(state.assoc.socket)
        :ok

      {:ok, {:abort, _}} ->
        discard_incoming(state)
        :gen_tcp.close(state.assoc.socket)
        {:error, :association_aborted}

      {:ok, other} ->
        abort(state, {:unexpected_pdu, other})

      {:error, reason} = error ->
        discard_incoming(state)
        close_after_error(state.assoc, reason)
        error
    end
  end

  defp handle_pdvs(state, []), do: serve_dimse(state)

  defp handle_pdvs(state, [pdv | rest]) do
    case handle_pdv(state, pdv) do
      {:ok, state} -> handle_pdvs(state, rest)
      {:error, reason} -> abort(state, reason)
    end
  end

  defp handle_pdv(state, pdv) do
    cond do
      not accepted_context?(state.assoc, pdv.context_id) ->
        {:error, {:unknown_presentation_context, pdv.context_id}}

      pdv.is_command and state.incoming != nil ->
        {:error, :unexpected_command}

      pdv.is_command ->
        handle_command_fragment(state, pdv)

      state.incoming == nil ->
        {:error, :unexpected_data_set}

      pdv.context_id != state.incoming.context_id ->
        {:error, {:unexpected_data_context, pdv.context_id}}

      true ->
        handle_data_fragment(state, pdv)
    end
  end

  defp handle_command_fragment(state, %{is_last: false} = pdv),
    do: {:ok, %{state | command: [state.command, pdv.data]}}

  defp handle_command_fragment(state, pdv) do
    with {:ok, command} <- DIMSE.decode_command(IO.iodata_to_binary([state.command, pdv.data])) do
      handle_command(%{state | command: []}, pdv.context_id, command)
    end
  end

  defp handle_command(state, context_id, %{command_field: CommandField.c_echo_rq()} = command) do
    rsp = DIMSE.build_cecho_rsp(command.message_id, Status.success())

    with :ok <- Association.send_pdata(state.assoc, context_id, true, rsp),
         do: {:ok, state}
  end

  defp handle_command(state, context_id, %{command_field: CommandField.c_store_rq()} = command) do
    cond do
      not storage_context?(state, context_id) ->
        {:error, {:unsupported_command, command.command_field}}

      DIMSE.dataset_present?(command.command_data_set_type) ->
        {:ok, %{state | incoming: start_store(state, context_id, command)}}

      true ->
        # Nothing will follow, so answer now rather than wait for a data set
        send_cstore_rsp(state, context_id, command, Status.cannot_understand())
    end
  end

  defp handle_command(_state, _context_id, command),
    do: {:error, {:unsupported_command, command.command_field}}

  # ===========================================================================
  # C-STORE
  # ===========================================================================

  # An instance we can't store is still read to its end, its data dropped as
  # it arrives, then answered with the failure status. The requestor sends the
  # whole data set without waiting for a reply, so this keeps the association
  # in step for its next instance, as dcmtk's storescp does.
  defp start_store(state, context_id, command) do
    instance = %{
      sop_class_uid: command.affected_sop_class_uid || "",
      sop_instance_uid: command.affected_sop_instance_uid,
      transfer_syntax: transfer_syntax(state.assoc, context_id)
    }

    store = %{context_id: context_id, command: command, instance: instance}
    opts = [source_ae_title: state.calling_ae_title]

    case InstanceFile.open(state.storage_directory, instance, opts) do
      {:ok, file} -> Map.merge(store, %{file: file, status: nil})
      {:error, status} -> Map.merge(store, %{file: nil, status: status})
    end
  end

  defp handle_data_fragment(state, pdv) do
    incoming = write_fragment(state.incoming, pdv.data)
    state = %{state | incoming: incoming}

    if pdv.is_last, do: complete_store(state), else: {:ok, state}
  end

  defp write_fragment(%{file: nil} = store, _data), do: store

  defp write_fragment(store, data) do
    case InstanceFile.write(store.file, data) do
      :ok -> store
      {:error, status} -> %{store | file: nil, status: status}
    end
  end

  defp complete_store(%{incoming: store} = state) do
    {status, state} = finish_store(%{state | incoming: nil}, store)
    send_cstore_rsp(state, store.context_id, store.command, status)
  end

  defp finish_store(state, %{file: nil, status: status}), do: {status, state}

  defp finish_store(state, store) do
    case InstanceFile.close(store.file) do
      {:ok, path} -> handle_store(state, store, path)
      {:error, status} -> {status, state}
    end
  end

  defp handle_store(%{handler: {module, handler_state}} = state, store, path) do
    instance =
      store.instance
      |> Map.merge(%{
        path: path,
        calling_ae_title: state.calling_ae_title,
        move_originator_ae_title: store.command.move_originator_ae_title,
        move_originator_message_id: store.command.move_originator_message_id
      })
      |> Map.merge(study_and_series_uids(path))

    {:reply, status, handler_state} = module.handle_store(instance, handler_state)
    {status, %{state | handler: {module, handler_state}}}
  end

  # Read back from the file's header, stopping before the pixel data, so a
  # handler can match an instance to a study or series move. A header that
  # can't be read leaves them nil; the instance still reaches the handler.
  defp study_and_series_uids(path) do
    case Dcmix.read_file(path, stop_before_pixels: true) do
      {:ok, header} ->
        %{
          study_instance_uid: DataSet.get_string(header, Tag.study_instance_uid()),
          series_instance_uid: DataSet.get_string(header, Tag.series_instance_uid())
        }

      {:error, _reason} ->
        %{study_instance_uid: nil, series_instance_uid: nil}
    end
  end

  defp send_cstore_rsp(state, context_id, command, status) do
    rsp =
      DIMSE.build_cstore_rsp(
        command.affected_sop_class_uid || "",
        command.affected_sop_instance_uid || "",
        command.message_id || 0,
        status
      )

    with :ok <- Association.send_pdata(state.assoc, context_id, true, rsp),
         do: {:ok, state}
  end

  defp discard_incoming(%{incoming: %{file: %InstanceFile{} = file}}),
    do: InstanceFile.discard(file)

  defp discard_incoming(_state), do: :ok

  # ===========================================================================
  # Contexts
  # ===========================================================================

  defp accepted_context?(assoc, context_id),
    do: Enum.any?(assoc.presentation_contexts, &(&1.id == context_id))

  defp storage_context?(%{handler: nil}, _context_id), do: false

  defp storage_context?(state, context_id) do
    case find_context(state.assoc, context_id) do
      %{abstract_syntax: abstract_syntax} -> abstract_syntax != SOPClassUID.verification()
      nil -> false
    end
  end

  defp transfer_syntax(assoc, context_id), do: find_context(assoc, context_id).transfer_syntax

  defp find_context(assoc, context_id),
    do: Enum.find(assoc.presentation_contexts, &(&1.id == context_id))

  # ===========================================================================
  # Closing
  # ===========================================================================

  defp abort(state, reason) do
    discard_incoming(state)
    Association.abort(state.assoc)
    {:error, reason}
  end

  defp close_after_error(assoc, reason) when reason in @desync_errors,
    do: Association.abort(assoc)

  defp close_after_error(assoc, {:recv_failed, :timeout}), do: Association.abort(assoc)
  defp close_after_error(assoc, _reason), do: :gen_tcp.close(assoc.socket)
end
