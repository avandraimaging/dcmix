defmodule Dcmix.Network.CMove do
  @moduledoc """
  High-level DICOM C-MOVE SCU operation.

  Asks a remote SCP to send the instances matching an identifier to a Storage
  SCP, the move destination, modelled on dcmtk's `movescu`. The instances
  travel over a separate association from the SCP to the destination, which
  may be another AE or a `Dcmix.Network.Listener` of our own; this
  association only carries the C-MOVE-RQ and the C-MOVE-RSPs.

  The identifier's Query/Retrieve Level (0008,0052) sets what is moved:
  `"PATIENT"`, `"STUDY"`, `"SERIES"` or `"IMAGE"`, with the unique keys for
  that level and those above it (e.g. Study, Series and SOP Instance UIDs to
  move one instance with the Study Root model, the default).

  ## Responses

  The SCP sends a pending C-MOVE-RSP as the sub-operations progress and a
  final one when they end. Each is given to the `:on_response` callback, if
  any, as a `Dcmix.Network.CMove.Response`; the callback returns `:cont` to
  carry on or `:cancel` to send a C-CANCEL-RQ. `move/3` returns the outcome
  once the final response arrives.

  ## Timeouts

  As with `Dcmix.Network.CGet`: if the SCP sends nothing for `:timeout` ms
  while we wait for its next response, a C-CANCEL-RQ is sent and the final
  C-MOVE-RSP awaited until a deadline of five seconds (or `:timeout`, if
  shorter) after the cancel. A cancel the callback asked for shares that
  deadline. The move returns `{:error, {:timeout, result}}`, with the counts
  reported so far, when the SCP answers that cancel with Cancel status or
  doesn't answer by the deadline. Any other final status is the SCP's answer
  and is returned as usual: a slow SCP may still have completed the move.
  """

  require Logger

  alias Dcmix.DataSet
  alias Dcmix.Network.{Association, DataSetCodec, DIMSE, SOPClassUID}
  alias Dcmix.Parser.TransferSyntax

  require Dcmix.Network.DIMSE.CommandField, as: CommandField
  require Dcmix.Network.DIMSE.Status, as: Status

  defmodule Response do
    @moduledoc """
    One C-MOVE-RSP, as given to the `:on_response` callback.

    `status` is the response's DIMSE status; `final` is true for the last
    response, whose status is the outcome of the move. The sub-operation
    counts are `nil` when the SCP left them out. `failed_sop_instance_uids`
    is the Failed SOP Instance UID List (0008,0058) from the response's
    identifier, if it carried one.
    """

    @type t :: %__MODULE__{
            status: non_neg_integer(),
            final: boolean(),
            remaining: non_neg_integer() | nil,
            completed: non_neg_integer() | nil,
            failed: non_neg_integer() | nil,
            warning: non_neg_integer() | nil,
            failed_sop_instance_uids: [String.t()]
          }

    defstruct [
      :status,
      :final,
      :remaining,
      :completed,
      :failed,
      :warning,
      failed_sop_instance_uids: []
    ]
  end

  defmodule Result do
    @moduledoc """
    Outcome of a C-MOVE.

    `status` is the status of the final C-MOVE-RSP. The sub-operation counts
    are those last reported by the SCP. `failed_sop_instance_uids` is the
    Failed SOP Instance UID List the SCP last reported, typically with a
    warning or failure status.
    """

    @type t :: %__MODULE__{
            status: non_neg_integer() | nil,
            completed: non_neg_integer(),
            failed: non_neg_integer(),
            warning: non_neg_integer(),
            failed_sop_instance_uids: [String.t()]
          }

    defstruct status: nil, completed: 0, failed: 0, warning: 0, failed_sop_instance_uids: []
  end

  @default_calling_ae "DCMIX"
  @default_called_ae "ANY-SCP"
  @default_query_model :study_root
  @default_message_id 1
  @default_priority 0x0000
  @default_timeout 30_000
  @default_max_pdu_length 16_384

  @message_ids 0..0xFFFF//1
  # Medium, high, low
  @priorities 0..2//1
  @max_ae_title_length 16

  @cancel_wait 5_000
  @failed_sop_instance_uid_list {0x0008, 0x0058}

  @doc """
  Performs a C-MOVE against a DICOM server.

  ## Parameters

  - `addr` - Server address as `"host:port"`
  - `identifier` - A `Dcmix.DataSet` holding the Query/Retrieve Level and
    the unique keys of what to move
  - `opts` - Options:
    - `:destination_ae_title` - AE title of the Storage SCP the instances
      are sent to; the SCP must know it (required: 1 to 16 characters, no
      backslash; surrounding spaces are dropped)
    - `:calling_ae_title` - Calling AE Title (default: `"DCMIX"`)
    - `:called_ae_title` - Called AE Title (default: `"ANY-SCP"`)
    - `:query_model` - `:study_root` (default) or `:patient_root`. Under
      Patient Root, moving a study, series or instance also needs the
      Patient ID in the identifier.
    - `:message_id` - Message ID of the C-MOVE-RQ, 0 to 65535 (default: 1).
      The SCP sends it back as the Move Originator Message ID of each
      C-STORE.
    - `:priority` - `0x0000` medium (default), `0x0001` high, `0x0002` low
    - `:on_response` - a function called with each
      `Dcmix.Network.CMove.Response`, returning `:cont` or `:cancel`
    - `:timeout` - TCP timeout in ms (default: 30000)
    - `:max_pdu_length` - Max PDU length to propose (default: 16384)
    - `:verbose` - Enable verbose logging (default: `false`)

  ## Returns

  - `{:ok, %Dcmix.Network.CMove.Result{}}` when the SCP sent a final
    C-MOVE-RSP, whatever its status (success, warning, failure or cancel),
    other than a Cancel answering a cancel we sent on timeout
  - `{:error, {:timeout, %Dcmix.Network.CMove.Result{}}}` when a read timed
    out once the request was sent and the SCP then cancelled, didn't answer
    the cancel, or stalled partway through a PDU (see the module docs)
  - `{:error, reason}` on connection, association or protocol failure, and
    before connecting for a missing or invalid option, e.g.
    `{:missing_option, :destination_ae_title}`,
    `{:invalid_destination_ae_title, title}`, `{:invalid_message_id, id}`,
    `{:invalid_priority, priority}` or `{:invalid_query_model, model}`

  ## Examples

      identifier =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0008, 0x0052}, :CS, "IMAGE")
        |> Dcmix.DataSet.put_element({0x0020, 0x000D}, :UI, "1.2.3")
        |> Dcmix.DataSet.put_element({0x0020, 0x000E}, :UI, "1.2.3.4")
        |> Dcmix.DataSet.put_element({0x0008, 0x0018}, :UI, "1.2.3.4.5")

      {:ok, %Dcmix.Network.CMove.Result{status: 0x0000}} =
        Dcmix.Network.CMove.move("pacs:4242", identifier,
          called_ae_title: "PACS_AE",
          destination_ae_title: "MY_SCP",
          on_response: fn response ->
            IO.puts("\#{response.remaining} remaining")
            :cont
          end
        )
  """
  @spec move(String.t(), DataSet.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def move(addr, %DataSet{} = identifier, opts \\ []) do
    with {:ok, config} <- config(opts),
         {:ok, move_uid} <- query_model_uid(Keyword.get(opts, :query_model, @default_query_model)),
         {:ok, assoc} <- Association.request(addr, association_opts(move_uid, config)) do
      log_verbose(config, "Association established")
      run_cmove(assoc, move_uid, identifier, config)
    end
  end

  # ===========================================================================
  # Setup
  # ===========================================================================

  # Checked before connecting, so a bad option is reported plainly rather than
  # as whatever the SCP makes of it
  defp config(opts) do
    message_id = Keyword.get(opts, :message_id, @default_message_id)
    priority = Keyword.get(opts, :priority, @default_priority)

    with {:ok, destination} <- destination(opts),
         :ok <- check(message_id in @message_ids, {:invalid_message_id, message_id}),
         :ok <- check(priority in @priorities, {:invalid_priority, priority}) do
      {:ok,
       %{
         destination: destination,
         calling_ae: Keyword.get(opts, :calling_ae_title, @default_calling_ae),
         called_ae: Keyword.get(opts, :called_ae_title, @default_called_ae),
         message_id: message_id,
         priority: priority,
         on_response: Keyword.get(opts, :on_response),
         timeout: Keyword.get(opts, :timeout, @default_timeout),
         max_pdu_length: Keyword.get(opts, :max_pdu_length, @default_max_pdu_length),
         verbose: Keyword.get(opts, :verbose, false)
       }}
    end
  end

  # An AE title is 1 to 16 characters of printable ASCII other than "\\";
  # surrounding spaces aren't significant, so they are dropped (PS3.5 6.2)
  defp destination(opts) do
    case Keyword.fetch(opts, :destination_ae_title) do
      {:ok, title} when is_binary(title) ->
        trimmed = String.trim(title, " ")

        valid =
          trimmed != "" and byte_size(trimmed) <= @max_ae_title_length and
            ae_title_chars?(trimmed)

        if valid, do: {:ok, trimmed}, else: {:error, {:invalid_destination_ae_title, title}}

      {:ok, title} ->
        {:error, {:invalid_destination_ae_title, title}}

      :error ->
        {:error, {:missing_option, :destination_ae_title}}
    end
  end

  defp ae_title_chars?(title),
    do: title |> :binary.bin_to_list() |> Enum.all?(&ae_title_char?/1)

  defp ae_title_char?(?\\), do: false
  defp ae_title_char?(c), do: c in 0x20..0x7E

  defp check(true, _error), do: :ok
  defp check(false, error), do: {:error, error}

  defp query_model_uid(:patient_root), do: {:ok, SOPClassUID.patient_root_query_retrieve_move()}
  defp query_model_uid(:study_root), do: {:ok, SOPClassUID.study_root_query_retrieve_move()}
  defp query_model_uid(other), do: {:error, {:invalid_query_model, other}}

  defp association_opts(move_uid, config) do
    [
      calling_ae_title: config.calling_ae,
      called_ae_title: config.called_ae,
      abstract_syntaxes: [move_uid],
      transfer_syntaxes: [
        TransferSyntax.explicit_vr_little_endian(),
        TransferSyntax.implicit_vr_little_endian()
      ],
      timeout: config.timeout,
      max_pdu_length: config.max_pdu_length
    ]
  end

  # ===========================================================================
  # Request / response loop
  # ===========================================================================

  defp run_cmove(assoc, move_uid, identifier, config) do
    with {:ok, pc} <- Association.accepted_context(assoc, move_uid),
         :ok <- send_request(assoc, pc, move_uid, identifier, config) do
      log_verbose(config, "C-MOVE request sent to move to #{config.destination}")

      state = %{
        assoc: assoc,
        config: config,
        context: pc,
        cancel: nil,
        command: [],
        response: nil,
        data: [],
        result: %Result{}
      }

      try do
        state |> receive_loop() |> finish()
      rescue
        # e.g. from the :on_response callback; the SCP must not carry on
        exception ->
          Association.abort(assoc)
          reraise exception, __STACKTRACE__
      end
    else
      {:error, :no_accepted_presentation_context} = error ->
        Association.release(assoc)
        error

      # A send that failed partway leaves the stream mid-message
      error ->
        Association.abort(assoc)
        error
    end
  end

  defp send_request(assoc, pc, move_uid, identifier, config) do
    command =
      DIMSE.build_cmove_rq(move_uid, config.message_id, config.destination, config.priority)

    with :ok <- Association.send_pdata(assoc, pc.id, true, command) do
      Association.send_pdata(
        assoc,
        pc.id,
        false,
        DataSetCodec.encode(identifier, pc.transfer_syntax)
      )
    end
  end

  defp finish({:done, state}) do
    Association.release(state.assoc)

    if cancelled_after_timeout?(state),
      do: {:error, {:timeout, state.result}},
      else: {:ok, state.result}
  end

  defp finish({:timed_out, state}) do
    Association.abort(state.assoc)
    {:error, {:timeout, state.result}}
  end

  defp finish({:error, reason, state}) do
    Association.abort(state.assoc)
    {:error, reason}
  end

  defp receive_loop(state) do
    case read_timeout(state) do
      :expired -> {:timed_out, state}
      timeout -> receive_next(state, timeout)
    end
  end

  # After a cancel, reads share one absolute deadline so an SCP that keeps
  # sending pending responses can't hold the call open forever
  defp read_timeout(%{cancel: nil, config: config}), do: config.timeout

  defp read_timeout(%{cancel: {_reason, deadline}}) do
    remaining = deadline - System.monotonic_time(:millisecond)
    if remaining > 0, do: remaining, else: :expired
  end

  defp receive_next(state, timeout) do
    case Association.receive_pdu(state.assoc, timeout) do
      {:ok, {:p_data, pdvs}} -> handle_pdvs(pdvs, state)
      {:ok, {:abort, _}} -> {:error, :association_aborted, state}
      {:ok, :release_rq} -> {:error, :unexpected_release, state}
      {:ok, other} -> {:error, {:unexpected_pdu, other}, state}
      {:error, {:recv_failed, :timeout}} -> cancel_after_timeout(state)
      {:error, :pdu_read_timeout} -> {:timed_out, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp handle_pdvs([], state), do: receive_loop(state)

  defp handle_pdvs([pdv | rest], state) do
    case handle_pdv(pdv, state) do
      {:cont, state} -> handle_pdvs(rest, state)
      other -> other
    end
  end

  defp handle_pdv(%{context_id: id}, %{context: %{id: expected}} = state) when id != expected,
    do: {:error, {:unexpected_context, id}, state}

  defp handle_pdv(%{is_command: true}, %{response: response} = state) when response != nil,
    do: {:error, :unexpected_command_fragment, state}

  defp handle_pdv(%{is_command: true, is_last: false, data: data}, state),
    do: {:cont, %{state | command: [state.command, data]}}

  defp handle_pdv(%{is_command: true} = pdv, state) do
    with {:ok, command} <- DIMSE.decode_command(IO.iodata_to_binary([state.command, pdv.data])),
         :ok <- check_response(command, state.config) do
      state = %{state | command: []}

      if DIMSE.dataset_present?(command.command_data_set_type),
        do: {:cont, %{state | response: command}},
        else: complete_response(command, nil, state)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp handle_pdv(_data_pdv, %{response: nil} = state),
    do: {:error, :unexpected_data_fragment, state}

  defp handle_pdv(%{is_last: false, data: data}, state),
    do: {:cont, %{state | data: [state.data, data]}}

  defp handle_pdv(pdv, state) do
    bytes = IO.iodata_to_binary([state.data, pdv.data])
    command = state.response
    state = %{state | response: nil, data: []}

    case DataSetCodec.decode(bytes, state.context.transfer_syntax) do
      {:ok, identifier} -> complete_response(command, identifier, state)
      {:error, reason} -> {:error, {:invalid_response_identifier, reason}, state}
    end
  end

  defp check_response(
         %{
           command_field: CommandField.c_move_rsp(),
           message_id_being_responded_to: id,
           status: status
         },
         %{message_id: id}
       )
       when is_integer(status),
       do: :ok

  defp check_response(command, _config), do: {:error, {:unexpected_response, command}}

  # ===========================================================================
  # Responses
  # ===========================================================================

  defp complete_response(command, identifier, state) do
    response = to_response(command, identifier)
    state = %{state | result: update_result(state.result, response)}
    log_verbose(state.config, "C-MOVE-RSP status 0x#{hex(response.status)}")

    case {call_back(state.config, response), response.final} do
      {_reply, true} -> {:done, state}
      {:cancel, false} -> send_cancel(state, :requested)
      {:cont, false} -> {:cont, state}
    end
  end

  defp to_response(command, identifier) do
    %Response{
      status: command.status,
      final: not DIMSE.status_pending?(command.status),
      remaining: command.remaining,
      completed: command.completed,
      failed: command.failed,
      warning: command.warning,
      failed_sop_instance_uids: failed_sop_instance_uids(identifier)
    }
  end

  defp update_result(result, response) do
    %{
      result
      | status: if(response.final, do: response.status, else: result.status),
        completed: response.completed || result.completed,
        failed: response.failed || result.failed,
        warning: response.warning || result.warning,
        failed_sop_instance_uids:
          if(response.failed_sop_instance_uids == [],
            do: result.failed_sop_instance_uids,
            else: response.failed_sop_instance_uids
          )
    }
  end

  defp call_back(%{on_response: nil}, _response), do: :cont

  defp call_back(%{on_response: on_response}, response) do
    case on_response.(response) do
      reply when reply in [:cont, :cancel] ->
        reply

      other ->
        raise ArgumentError,
              ":on_response must return :cont or :cancel, got: #{inspect(other)}"
    end
  end

  # A multi-valued UI decodes as one string, values separated by "\\"
  defp failed_sop_instance_uids(nil), do: []

  defp failed_sop_instance_uids(identifier) do
    case DataSet.get_value(identifier, @failed_sop_instance_uid_list) do
      value when is_binary(value) ->
        value
        |> String.trim_trailing(<<0>>)
        |> String.split("\\", trim: true)
        |> Enum.map(&String.trim/1)

      _other ->
        []
    end
  end

  # A cancel we sent because the SCP went quiet ends as a timeout only if the
  # SCP did cancel. Any other final status is its answer: a slow SCP may have
  # finished every sub-operation, and reporting that as a failure would invite
  # the caller to move it all again.
  defp cancelled_after_timeout?(%{cancel: {:timeout, _deadline}, result: result}),
    do: result.status == Status.cancel()

  defp cancelled_after_timeout?(_state), do: false

  # A read timeout before any cancel sends one; after a cancel, reads are
  # bounded by its deadline, so a timeout then means it has passed
  defp cancel_after_timeout(%{cancel: nil} = state) do
    case send_cancel(state, :timeout) do
      {:cont, state} -> receive_loop(state)
      error -> error
    end
  end

  defp cancel_after_timeout(state), do: {:timed_out, state}

  # Sends at most one C-CANCEL-RQ; asking again changes nothing
  defp send_cancel(%{cancel: nil} = state, reason) do
    log_verbose(state.config, "Sending C-CANCEL-RQ (#{reason})")
    command = DIMSE.build_ccancel_rq(state.config.message_id)
    deadline = System.monotonic_time(:millisecond) + min(state.config.timeout, @cancel_wait)

    case Association.send_pdata(state.assoc, state.context.id, true, command) do
      :ok -> {:cont, %{state | cancel: {reason, deadline}}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp send_cancel(state, _reason), do: {:cont, state}

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp hex(nil), do: "????"
  defp hex(value), do: value |> Integer.to_string(16) |> String.pad_leading(4, "0")

  defp log_verbose(%{verbose: true}, message), do: Logger.info("[CMove] #{message}")
  defp log_verbose(_config, _message), do: :ok
end
