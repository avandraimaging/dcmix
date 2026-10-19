defmodule Dcmix.Network.CMoveTest do
  use ExUnit.Case, async: true

  alias Dcmix.DataSet
  alias Dcmix.Network
  alias Dcmix.Network.{Association, CMove, DataSetCodec, DIMSE, PDU, SOPClassUID}
  alias Dcmix.Network.CMove.{Response, Result}
  alias Dcmix.Parser.TransferSyntax

  import ExUnit.CaptureLog

  require Dcmix.Network.DIMSE.CommandField, as: CommandField
  require Dcmix.Network.DIMSE.Status, as: Status

  @study_root_move SOPClassUID.study_root_query_retrieve_move()
  @patient_root_move SOPClassUID.patient_root_query_retrieve_move()

  describe "move/3 - request" do
    test "asks the SCP to move the identifier's instances to the destination" do
      {addr, scp} =
        start_scp(fn assoc ->
          {pc_id, command, identifier} = receive_request(assoc)
          report({:request, command, identifier})
          send_rsp(assoc, pc_id, command.message_id, Status.success(), completed: 3)
        end)

      assert {:ok, %Result{status: Status.success(), completed: 3}} =
               CMove.move(addr, instance_identifier(),
                 destination_ae_title: "MY_SCP",
                 query_model: :study_root,
                 message_id: 42,
                 priority: 0x0001
               )

      assert_receive {:associate_rq,
                      %{presentation_contexts: [%{abstract_syntax: @study_root_move}]}}

      assert_receive {:request, command, identifier}
      assert command.command_field == CommandField.c_move_rq()
      assert command.affected_sop_class_uid == @study_root_move
      assert command.message_id == 42
      assert DataSet.get_string(identifier, {0x0008, 0x0052}) == "IMAGE"
      assert DataSet.get_string(identifier, {0x0008, 0x0018}) == "1.2.3.4.5"
      wait_for(scp)
    end

    test "sends the move destination and priority in the C-MOVE-RQ" do
      command = DIMSE.build_cmove_rq(@study_root_move, 7, "MY_SCP", 0x0002)

      assert :binary.match(command, <<0x00, 0x00, 0x00, 0x06, 6::32-little, "MY_SCP">>) !=
               :nomatch

      assert :binary.match(command, <<0x00, 0x00, 0x00, 0x07, 2::32-little, 2::16-little>>) !=
               :nomatch
    end

    test "uses the Patient Root model by default" do
      {addr, scp} = start_scp(&answer_success/1)

      assert {:ok, _result} =
               CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP")

      assert_receive {:associate_rq,
                      %{presentation_contexts: [%{abstract_syntax: @patient_root_move}]}}

      wait_for(scp)
    end

    test "is reachable as Dcmix.Network.move/3" do
      {addr, scp} = start_scp(&answer_success/1)

      assert {:ok, %Result{status: Status.success()}} =
               Network.move(addr, instance_identifier(), destination_ae_title: "MY_SCP")

      wait_for(scp)
    end
  end

  describe "move/3 - responses" do
    test "gives each response to :on_response, then returns the final counts" do
      {addr, scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          send_rsp(assoc, pc_id, command.message_id, Status.pending(), remaining: 2, completed: 0)
          send_rsp(assoc, pc_id, command.message_id, Status.pending(), remaining: 1, completed: 1)
          send_rsp(assoc, pc_id, command.message_id, Status.success(), completed: 2)
        end)

      test = self()

      assert {:ok, result} =
               CMove.move(addr, instance_identifier(),
                 destination_ae_title: "MY_SCP",
                 on_response: fn response ->
                   send(test, {:response, response})
                   :cont
                 end
               )

      assert result == %Result{status: Status.success(), completed: 2}

      assert_receive {:response,
                      %Response{
                        status: Status.pending(),
                        final: false,
                        remaining: 2,
                        completed: 0
                      }}

      assert_receive {:response, %Response{remaining: 1, completed: 1, final: false}}
      assert_receive {:response, %Response{status: Status.success(), final: true, completed: 2}}
      wait_for(scp)
    end

    test "returns the Failed SOP Instance UID List from the final response" do
      failed = "1.2.3.4.5\\1.2.3.4.6"

      {addr, scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          identifier = DataSet.put_element(DataSet.new(), {0x0008, 0x0058}, :UI, failed)

          send_rsp(
            assoc,
            pc_id,
            command.message_id,
            Status.sub_operations_complete_with_failures(),
            completed: 1,
            failed: 2,
            identifier: identifier
          )
        end)

      assert {:ok, result} =
               CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP")

      assert result.status == Status.sub_operations_complete_with_failures()
      assert result.failed == 2
      assert result.failed_sop_instance_uids == ["1.2.3.4.5", "1.2.3.4.6"]
      wait_for(scp)
    end

    test "returns no failed instances for an identifier without the list" do
      {addr, scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          identifier = DataSet.put_element(DataSet.new(), {0x0008, 0x0052}, :CS, "IMAGE")
          send_rsp(assoc, pc_id, command.message_id, Status.success(), identifier: identifier)
        end)

      assert {:ok, %Result{failed_sop_instance_uids: []}} =
               CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP")

      wait_for(scp)
    end

    test "returns a failure status as the outcome" do
      {addr, scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          send_rsp(assoc, pc_id, command.message_id, Status.move_destination_unknown())
        end)

      assert {:ok, %Result{status: Status.move_destination_unknown()}} =
               CMove.move(addr, instance_identifier(), destination_ae_title: "UNKNOWN")

      wait_for(scp)
    end

    test "reads a response command and its identifier, each split across PDVs" do
      {addr, scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)

          rsp =
            cmove_rsp(command.message_id, Status.sub_operations_complete_with_failures(),
              failed: 1,
              identifier: true
            )

          <<first::binary-size(12), rest::binary>> = rsp
          identifier = DataSet.put_element(DataSet.new(), {0x0008, 0x0058}, :UI, "1.2.3.4.5")

          <<id_first::binary-size(6), id_rest::binary>> = encode(identifier)

          send_raw(assoc, PDU.encode_p_data(pc_id, true, false, first))
          send_raw(assoc, PDU.encode_p_data(pc_id, true, true, rest))
          send_raw(assoc, PDU.encode_p_data(pc_id, false, false, id_first))
          send_raw(assoc, PDU.encode_p_data(pc_id, false, true, id_rest))
          handle_release(assoc)
        end)

      assert {:ok, %Result{failed: 1, failed_sop_instance_uids: ["1.2.3.4.5"]}} =
               CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP")

      wait_for(scp)
    end
  end

  describe "move/3 - cancel" do
    test "sends a C-CANCEL-RQ when :on_response asks, once, and returns the SCP's outcome" do
      {addr, scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          send_rsp(assoc, pc_id, command.message_id, Status.pending(), remaining: 3, completed: 0)
          send_rsp(assoc, pc_id, command.message_id, Status.pending(), remaining: 2, completed: 1)
          {_pc_id, cancel} = receive_command(assoc)
          report({:cancel, cancel})

          rsp = cmove_rsp(command.message_id, Status.cancel(), completed: 1)
          :ok = Association.send_pdata(assoc, pc_id, true, rsp)

          # A second C-CANCEL-RQ would arrive here instead of the release
          next = Association.receive_pdu(assoc, 5_000)
          report({:after_final, next})
          send_raw(assoc, PDU.encode_release_rp())
        end)

      assert {:ok, %Result{status: Status.cancel(), completed: 1}} =
               CMove.move(addr, instance_identifier(),
                 destination_ae_title: "MY_SCP",
                 message_id: 9,
                 on_response: fn _response -> :cancel end
               )

      assert_receive {:cancel, cancel}
      assert cancel.command_field == CommandField.c_cancel_rq()
      assert cancel.message_id_being_responded_to == 9
      assert_receive {:after_final, {:ok, :release_rq}}
      wait_for(scp)
    end

    test "raises when :on_response returns anything else" do
      {addr, _scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          send_rsp(assoc, pc_id, command.message_id, Status.pending(), remaining: 1)
          Process.sleep(1_000)
        end)

      assert_raise ArgumentError, ~r/must return :cont or :cancel/, fn ->
        CMove.move(addr, instance_identifier(),
          destination_ae_title: "MY_SCP",
          on_response: fn _response -> :ok end
        )
      end
    end
  end

  describe "move/3 - logging" do
    test "logs the request and each response when verbose" do
      {addr, scp} = start_scp(&answer_success/1)

      log =
        capture_log(fn ->
          assert {:ok, _result} =
                   CMove.move(addr, instance_identifier(),
                     destination_ae_title: "MY_SCP",
                     verbose: true
                   )
        end)

      assert log =~ "[CMove] C-MOVE request sent to move to MY_SCP"
      assert log =~ "[CMove] C-MOVE-RSP status 0x0000"
      wait_for(scp)
    end
  end

  describe "move/3 - timeouts" do
    test "cancels when the SCP goes quiet and returns its final counts as a timeout" do
      {addr, scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          send_rsp(assoc, pc_id, command.message_id, Status.pending(), remaining: 2, completed: 1)
          {_pc_id, cancel} = receive_command(assoc)
          report({:cancel, cancel})
          send_rsp(assoc, pc_id, command.message_id, Status.cancel(), completed: 1)
        end)

      assert {:error, {:timeout, %Result{status: Status.cancel(), completed: 1}}} =
               CMove.move(addr, instance_identifier(),
                 destination_ae_title: "MY_SCP",
                 timeout: 200
               )

      assert_receive {:cancel, %{command_field: CommandField.c_cancel_rq()}}
      wait_for(scp)
    end

    test "stops at the cancel deadline when the SCP keeps sending pending responses" do
      {addr, _scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)

          for completed <- 1..30 do
            send_rsp(assoc, pc_id, command.message_id, Status.pending(), completed: completed)
            Process.sleep(50)
          end
        end)

      assert {:error, {:timeout, %Result{status: nil}}} =
               CMove.move(addr, instance_identifier(),
                 destination_ae_title: "MY_SCP",
                 timeout: 200,
                 on_response: fn _response -> :cancel end
               )
    end

    test "gives up on a response that stalls partway through its PDU" do
      {addr, _scp} =
        start_scp(fn assoc ->
          _request = receive_request(assoc)
          send_raw(assoc, <<0x04, 0x00, 100::32-big, 0, 0>>)
          Process.sleep(1_000)
        end)

      assert {:error, {:timeout, %Result{}}} =
               CMove.move(addr, instance_identifier(),
                 destination_ae_title: "MY_SCP",
                 timeout: 200
               )
    end

    test "gives up when the SCP doesn't answer the cancel either" do
      {addr, _scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          send_rsp(assoc, pc_id, command.message_id, Status.pending(), remaining: 2, completed: 1)
          Process.sleep(2_000)
        end)

      assert {:error, {:timeout, %Result{status: nil, completed: 1}}} =
               CMove.move(addr, instance_identifier(),
                 destination_ae_title: "MY_SCP",
                 timeout: 200
               )
    end
  end

  describe "move/3 - failures" do
    test "a response to another message" do
      {addr, _scp} =
        start_scp(fn assoc ->
          {pc_id, _command, _identifier} = receive_request(assoc)
          send_rsp(assoc, pc_id, 99, Status.success())
          Process.sleep(500)
        end)

      assert {:error, {:unexpected_response, %{message_id_being_responded_to: 99}}} =
               CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP")
    end

    test "a release request from the SCP" do
      {addr, _scp} =
        start_scp(fn assoc ->
          _request = receive_request(assoc)
          send_raw(assoc, PDU.encode_release_rq())
          Process.sleep(500)
        end)

      assert CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP") ==
               {:error, :unexpected_release}
    end

    test "a PDU that isn't P-DATA" do
      {addr, _scp} =
        start_scp(fn assoc ->
          _request = receive_request(assoc)
          send_raw(assoc, PDU.encode_release_rp())
          Process.sleep(500)
        end)

      assert {:error, {:unexpected_pdu, :release_rp}} =
               CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP")
    end

    test "a response on another presentation context" do
      {addr, _scp} =
        start_scp(fn assoc ->
          {_pc_id, command, _identifier} = receive_request(assoc)
          send_raw(assoc, PDU.encode_p_data(99, true, true, cmove_rsp(command.message_id, 0, [])))
          Process.sleep(500)
        end)

      assert CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP") ==
               {:error, {:unexpected_context, 99}}
    end

    test "a data set before any response" do
      {addr, _scp} =
        start_scp(fn assoc ->
          {pc_id, _command, _identifier} = receive_request(assoc)
          send_raw(assoc, PDU.encode_p_data(pc_id, false, true, <<>>))
          Process.sleep(500)
        end)

      assert CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP") ==
               {:error, :unexpected_data_fragment}
    end

    test "a command where a response's identifier is expected" do
      {addr, _scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          rsp = cmove_rsp(command.message_id, Status.success(), identifier: true)
          :ok = Association.send_pdata(assoc, pc_id, true, rsp)
          :ok = Association.send_pdata(assoc, pc_id, true, rsp)
          Process.sleep(500)
        end)

      assert CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP") ==
               {:error, :unexpected_command_fragment}
    end

    test "a response identifier that doesn't decode" do
      {addr, _scp} =
        start_scp(fn assoc ->
          {pc_id, command, _identifier} = receive_request(assoc)
          rsp = cmove_rsp(command.message_id, Status.success(), identifier: true)
          :ok = Association.send_pdata(assoc, pc_id, true, rsp)
          truncated = <<0x08, 0x00, 0x58, 0x00, "UI", 100::16-little, "1.2">>
          :ok = Association.send_pdata(assoc, pc_id, false, truncated)
          Process.sleep(500)
        end)

      assert {:error, {:invalid_response_identifier, _reason}} =
               CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP")
    end

    test "the SCP closing the connection" do
      {addr, _scp} = start_scp(fn assoc -> _request = receive_request(assoc) end)

      assert {:error, {:recv_failed, :closed}} =
               CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP")
    end

    test "an abort from the SCP" do
      {addr, scp} =
        start_scp(fn assoc ->
          _request = receive_request(assoc)
          send_raw(assoc, PDU.encode_abort())
        end)

      assert CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP") ==
               {:error, :association_aborted}

      wait_for(scp)
    end

    test "an SCP that doesn't accept the MOVE context" do
      {addr, scp} = start_scp(&handle_release/1, accept: false)

      assert CMove.move(addr, instance_identifier(), destination_ae_title: "MY_SCP") ==
               {:error, :no_accepted_presentation_context}

      wait_for(scp)
    end

    test "an unknown query model" do
      assert CMove.move("localhost:1", instance_identifier(),
               destination_ae_title: "MY_SCP",
               query_model: :relational
             ) == {:error, {:invalid_query_model, :relational}}
    end

    test "requires a destination" do
      assert_raise KeyError, fn -> CMove.move("localhost:1", instance_identifier()) end
    end
  end

  # ===========================================================================
  # A scripted MOVE SCP
  # ===========================================================================

  defp start_scp(script, opts \\ []) do
    accept = Keyword.get(opts, :accept, true)
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    test = self()

    scp =
      spawn_link(fn ->
        Process.put(:test, test)
        {:ok, socket} = :gen_tcp.accept(listen, 5_000)
        {:ok, {:associate_rq, rq}} = Association.receive_pdu(%Association{socket: socket}, 5_000)
        send(test, {:associate_rq, rq})

        contexts =
          for pc <- rq.presentation_contexts do
            %{
              id: pc.id,
              result: if(accept, do: 0, else: 3),
              transfer_syntax: TransferSyntax.explicit_vr_little_endian()
            }
          end

        :ok = :gen_tcp.send(socket, PDU.encode_associate_ac(rq, contexts))

        assoc = %Association{
          socket: socket,
          max_pdu_length: rq.max_pdu_length,
          presentation_contexts: contexts
        }

        script.(assoc)
        :gen_tcp.close(socket)
        :gen_tcp.close(listen)
        send(test, {:scp_done, self()})
      end)

    {"localhost:#{port}", scp}
  end

  defp report(message), do: send(Process.get(:test), message)

  defp wait_for(scp) do
    assert_receive {:scp_done, ^scp}, 5_000
  end

  defp answer_success(assoc) do
    {pc_id, command, _identifier} = receive_request(assoc)
    send_rsp(assoc, pc_id, command.message_id, Status.success())
  end

  defp receive_request(assoc) do
    {pc_id, command} = receive_command(assoc)
    {:ok, identifier} = DataSetCodec.decode(receive_fragments(assoc, false), explicit())
    {pc_id, command, identifier}
  end

  defp receive_command(assoc) do
    {:ok, {:p_data, pdvs}} = Association.receive_pdu(assoc, 5_000)
    [%{is_command: true, context_id: pc_id} | _] = pdvs
    {:ok, command} = DIMSE.decode_command(collect(pdvs, true))
    {pc_id, command}
  end

  defp receive_fragments(assoc, is_command, acc \\ <<>>) do
    {:ok, {:p_data, pdvs}} = Association.receive_pdu(assoc, 5_000)
    data = acc <> collect(pdvs, is_command)

    if Enum.any?(pdvs, &(&1.is_command == is_command and &1.is_last)),
      do: data,
      else: receive_fragments(assoc, is_command, data)
  end

  defp collect(pdvs, is_command),
    do: for(%{is_command: ^is_command, data: data} <- pdvs, into: <<>>, do: data)

  # Sends a C-MOVE-RSP, and once the final one is sent, answers the release
  defp send_rsp(assoc, pc_id, message_id, status, opts \\ []) do
    identifier = Keyword.get(opts, :identifier)
    rsp = cmove_rsp(message_id, status, Keyword.put(opts, :identifier, identifier != nil))
    :ok = Association.send_pdata(assoc, pc_id, true, rsp)
    if identifier, do: :ok = Association.send_pdata(assoc, pc_id, false, encode(identifier))
    unless DIMSE.status_pending?(status), do: handle_release(assoc)
  end

  defp handle_release(assoc) do
    case Association.receive_pdu(assoc, 5_000) do
      {:ok, :release_rq} -> send_raw(assoc, PDU.encode_release_rp())
      _other -> :ok
    end
  end

  defp send_raw(assoc, pdu), do: :ok = :gen_tcp.send(assoc.socket, pdu)

  defp encode(data_set), do: DataSetCodec.encode(data_set, explicit())

  defp explicit, do: TransferSyntax.explicit_vr_little_endian()

  # C-MOVE-RSP command set (Implicit VR Little Endian)
  defp cmove_rsp(message_id, status, opts) do
    counts =
      for {key, element} <- [
            remaining: 0x1020,
            completed: 0x1021,
            failed: 0x1022,
            warning: 0x1023
          ],
          value = Keyword.get(opts, key),
          value != nil,
          do: {element, <<value::16-little>>}

    data_set_type = if Keyword.get(opts, :identifier, false), do: 0x0000, else: 0x0101

    elements =
      [
        {0x0002, pad(@study_root_move)},
        {0x0100, <<CommandField.c_move_rsp()::16-little>>},
        {0x0120, <<message_id::16-little>>},
        {0x0800, <<data_set_type::16-little>>},
        {0x0900, <<status::16-little>>}
      ] ++ counts

    body =
      for {element, value} <- Enum.sort(elements), into: <<>> do
        <<0x0000::16-little, element::16-little, byte_size(value)::32-little, value::binary>>
      end

    <<0::16, 0::16, 4::32-little, byte_size(body)::32-little, body::binary>>
  end

  defp pad(uid) when rem(byte_size(uid), 2) == 1, do: uid <> <<0>>
  defp pad(uid), do: uid

  defp instance_identifier do
    DataSet.new()
    |> DataSet.put_element({0x0008, 0x0052}, :CS, "IMAGE")
    |> DataSet.put_element({0x0020, 0x000D}, :UI, "1.2.3")
    |> DataSet.put_element({0x0020, 0x000E}, :UI, "1.2.3.4")
    |> DataSet.put_element({0x0008, 0x0018}, :UI, "1.2.3.4.5")
  end
end
