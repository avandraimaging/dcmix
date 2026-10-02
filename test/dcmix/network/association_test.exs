defmodule Dcmix.Network.AssociationTest do
  use ExUnit.Case

  alias Dcmix.Network.{Association, PDU}

  @implicit_vr_le "1.2.840.10008.1.2"

  describe "request/2" do
    test "establishes association with mock server" do
      {port, server_pid} = start_mock_server(:accept)

      assert {:ok, assoc} =
               Association.request("127.0.0.1:#{port}",
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP",
                 timeout: 5_000
               )

      assert %Association{} = assoc
      assert assoc.max_pdu_length == 65_536

      assert {:ok, pc} = Association.accepted_context(assoc)
      assert pc.id == 1
      assert pc.result == 0
      assert pc.transfer_syntax == @implicit_vr_le

      Association.release(assoc)
      wait_for_server(server_pid)
    end

    test "returns error on connection refused" do
      # Use a port that's (very likely) not listening
      assert {:error, {:connection_failed, _}} =
               Association.request("127.0.0.1:1", timeout: 1_000)
    end

    test "returns error on association rejection" do
      {port, server_pid} = start_mock_server(:reject)

      assert {:error, {:association_rejected, 1, 7}} =
               Association.request("127.0.0.1:#{port}", timeout: 5_000)

      wait_for_server(server_pid)
    end

    test "returns error for invalid address" do
      assert {:error, {:invalid_address, "no-port"}} =
               Association.request("no-port")
    end

    test "returns error for invalid port" do
      assert {:error, {:invalid_port, "abc"}} =
               Association.request("localhost:abc")
    end
  end

  describe "request/2 - presentation_contexts option" do
    @ct_storage "1.2.840.10008.5.1.4.1.1.2"
    @mr_storage "1.2.840.10008.5.1.4.1.1.4"
    @patient_root_get "1.2.840.10008.5.1.4.1.2.1.3"

    test "proposes each context and annotates the accepted ones with syntax and roles" do
      {port, server_pid} = start_mock_server({:roles, self()})

      assert {:ok, assoc} =
               Association.request("127.0.0.1:#{port}",
                 timeout: 5_000,
                 presentation_contexts: [
                   %{abstract_syntax: @patient_root_get, transfer_syntaxes: [@implicit_vr_le]},
                   %{
                     abstract_syntax: @ct_storage,
                     transfer_syntaxes: [@implicit_vr_le],
                     scu_role: false,
                     scp_role: true
                   },
                   %{
                     abstract_syntax: @mr_storage,
                     transfer_syntaxes: [@implicit_vr_le],
                     scp_role: true
                   }
                 ]
               )

      assert_receive {:associate_rq, rq}, 5_000
      assert :binary.match(rq, @patient_root_get) != :nomatch
      ct_role = <<0x54, 0x00, 29::16-big, 25::16-big, @ct_storage::binary, 0, 1>>
      mr_role = <<0x54, 0x00, 29::16-big, 25::16-big, @mr_storage::binary, 0, 1>>
      assert :binary.match(rq, ct_role) != :nomatch
      assert :binary.match(rq, mr_role) != :nomatch
      # No role item for the GET context, which asked for none
      assert :binary.matches(rq, <<0x54, 0x00>>) |> length() == 2

      assert [get, ct, mr] = assoc.presentation_contexts
      assert %{id: 1, result: 0, abstract_syntax: @patient_root_get, scp_role: nil} = get

      assert %{id: 3, result: 0, abstract_syntax: @ct_storage, scu_role: false, scp_role: true} =
               ct

      assert %{id: 5, result: 3, abstract_syntax: @mr_storage} = mr

      assert {:ok, %{id: 3}} = Association.accepted_context(assoc, @ct_storage)

      assert {:error, :no_accepted_presentation_context} =
               Association.accepted_context(assoc, @mr_storage)

      Association.release(assoc)
      wait_for_server(server_pid)
    end

    test "legacy options still produce annotated contexts" do
      {port, server_pid} = start_mock_server(:accept)

      assert {:ok, assoc} =
               Association.request("127.0.0.1:#{port}",
                 abstract_syntaxes: ["1.2.840.10008.5.1.4.1.2.2.1"],
                 transfer_syntaxes: [@implicit_vr_le],
                 timeout: 5_000
               )

      assert {:ok, %{id: 1, abstract_syntax: "1.2.840.10008.5.1.4.1.2.2.1"}} =
               Association.accepted_context(assoc, "1.2.840.10008.5.1.4.1.2.2.1")

      Association.release(assoc)
      wait_for_server(server_pid)
    end
  end

  describe "send_pdata/4 - fragmentation" do
    test "splits data over PDUs no larger than the peer's maximum" do
      {port, server_pid} = start_mock_server({:fragments, self()})

      {:ok, assoc} = Association.request("127.0.0.1:#{port}", timeout: 5_000)
      assert assoc.max_pdu_length == 20

      data = :binary.copy(<<7>>, 40)
      assert :ok = Association.send_pdata(assoc, 1, false, data)

      assert_receive {:fragments, pdvs}, 5_000
      assert Enum.map(pdvs, &byte_size(&1.data)) == [14, 14, 12]
      assert Enum.map(pdvs, & &1.is_last) == [false, false, true]
      assert pdvs |> Enum.map(& &1.data) |> IO.iodata_to_binary() == data

      Association.release(assoc)
      wait_for_server(server_pid)
    end
  end

  describe "send_pdata/4 and receive_pdu/1" do
    test "sends and receives P-DATA through mock server echo" do
      {port, server_pid} = start_mock_server(:echo_pdata)

      {:ok, assoc} =
        Association.request("127.0.0.1:#{port}",
          calling_ae_title: "TEST_SCU",
          called_ae_title: "TEST_SCP",
          timeout: 5_000
        )

      {:ok, pc} = Association.accepted_context(assoc)

      # Send a command P-DATA
      test_data = <<1, 2, 3, 4, 5>>
      assert :ok = Association.send_pdata(assoc, pc.id, true, test_data)

      # Receive echoed P-DATA
      assert {:ok, {:p_data, [pdv]}} = Association.receive_pdu(assoc)
      assert pdv.data == test_data
      assert pdv.is_command == true

      Association.release(assoc)
      wait_for_server(server_pid)
    end
  end

  describe "accepted_context/1" do
    test "returns error when no contexts accepted" do
      assoc = %Association{
        socket: nil,
        max_pdu_length: 16_384,
        presentation_contexts: [%{id: 1, result: 1, transfer_syntax: ""}]
      }

      assert {:error, :no_accepted_presentation_context} =
               Association.accepted_context(assoc)
    end
  end

  describe "abort/1" do
    test "sends abort PDU and closes socket" do
      {port, server_pid} = start_mock_server(:accept)

      {:ok, assoc} =
        Association.request("127.0.0.1:#{port}",
          calling_ae_title: "TEST_SCU",
          called_ae_title: "TEST_SCP",
          timeout: 5_000
        )

      assert :ok = Association.abort(assoc)
      wait_for_server(server_pid)
    end
  end

  describe "request/2 - association aborted by server" do
    test "returns error when server sends abort" do
      {port, server_pid} = start_mock_server(:abort)

      assert {:error, {:association_aborted, 2, 0}} =
               Association.request("127.0.0.1:#{port}", timeout: 5_000)

      wait_for_server(server_pid)
    end
  end

  describe "request/2 - unexpected PDU from server" do
    test "returns error for unexpected PDU type" do
      {port, server_pid} = start_mock_server(:unexpected)

      assert {:error, {:unexpected_pdu, _}} =
               Association.request("127.0.0.1:#{port}", timeout: 5_000)

      wait_for_server(server_pid)
    end
  end

  describe "receive_pdu/2 - PDU length and partial reads" do
    test "records the proposed maximum as the local limit" do
      {port, server_pid} = start_mock_server({:send_after_accept, <<>>})

      {:ok, assoc} =
        Association.request("127.0.0.1:#{port}", timeout: 5_000, max_pdu_length: 4_096)

      assert assoc.local_max_pdu_length == 4_096
      assert assoc.max_pdu_length == 65_536

      Association.abort(assoc)
      wait_for_server(server_pid)
    end

    test "rejects a P-DATA PDU longer than the local maximum without reading it" do
      {port, server_pid} = start_mock_server({:send_after_accept, p_data_of_length(1_025)})

      {:ok, assoc} =
        Association.request("127.0.0.1:#{port}", timeout: 5_000, max_pdu_length: 1_024)

      assert {:error, :pdu_too_large} = Association.receive_pdu(assoc, 1_000)
      Association.abort(assoc)
      wait_for_server(server_pid)
    end

    test "accepts a P-DATA PDU exactly at the local maximum" do
      {port, server_pid} = start_mock_server({:send_after_accept, p_data_of_length(1_024)})

      {:ok, assoc} =
        Association.request("127.0.0.1:#{port}", timeout: 5_000, max_pdu_length: 1_024)

      assert {:ok, {:p_data, [%{data: data}]}} = Association.receive_pdu(assoc, 1_000)
      assert byte_size(data) == 1_024 - 6
      Association.abort(assoc)
      wait_for_server(server_pid)
    end

    test "a local maximum of 0 means unlimited" do
      {port, server_pid} = start_mock_server({:send_after_accept, p_data_of_length(70_000)})

      {:ok, assoc} = Association.request("127.0.0.1:#{port}", timeout: 5_000, max_pdu_length: 0)

      assert {:ok, {:p_data, [_]}} = Association.receive_pdu(assoc, 1_000)
      Association.abort(assoc)
      wait_for_server(server_pid)
    end

    test "a stall after the PDU header is a distinct error" do
      header_only = <<0x04, 0x00, 100::32-big, 0, 0>>
      {port, server_pid} = start_mock_server({:send_after_accept, header_only})

      {:ok, assoc} = Association.request("127.0.0.1:#{port}", timeout: 5_000)

      assert {:error, :pdu_read_timeout} = Association.receive_pdu(assoc, 300)
      Association.abort(assoc)
      wait_for_server(server_pid)
    end
  end

  describe "receive_pdu/1 - timeout" do
    test "returns error when receive times out" do
      {port, server_pid} = start_mock_server(:accept_no_release)

      {:ok, assoc} =
        Association.request("127.0.0.1:#{port}",
          calling_ae_title: "TEST_SCU",
          called_ae_title: "TEST_SCP",
          timeout: 5_000
        )

      # Try to receive when server won't send anything — should timeout
      assert {:error, {:recv_failed, :timeout}} = Association.receive_pdu(assoc, 500)

      Association.abort(assoc)
      wait_for_server(server_pid)
    end
  end

  # ===========================================================================
  # Mock DICOM Server
  # ===========================================================================

  defp start_mock_server(mode) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    parent = self()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          run_mock_server(socket, mode)
          :gen_tcp.close(socket)
        after
          :gen_tcp.close(listen)
          send(parent, {:server_done, self()})
        end
      end)

    {port, pid}
  end

  defp wait_for_server(pid) do
    receive do
      {:server_done, ^pid} -> :ok
    after
      5_000 -> :ok
    end
  end

  defp run_mock_server(socket, :accept) do
    # Read A-ASSOCIATE-RQ
    {:ok, _rq} = recv_full_pdu(socket)

    # Send A-ASSOCIATE-AC
    ac_pdu = build_associate_ac()
    :ok = :gen_tcp.send(socket, ac_pdu)

    # Wait for release or close
    case recv_full_pdu(socket) do
      {:ok, _} ->
        # Send release response
        :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)

      {:error, :closed} ->
        :ok
    end
  end

  defp run_mock_server(socket, :reject) do
    # Read A-ASSOCIATE-RQ
    {:ok, _rq} = recv_full_pdu(socket)

    # Send A-ASSOCIATE-RJ
    :ok = :gen_tcp.send(socket, <<0x03, 0x00, 4::32-big, 0x00, 0x00, 1, 7>>)
  end

  defp run_mock_server(socket, :abort) do
    # Read A-ASSOCIATE-RQ
    {:ok, _rq} = recv_full_pdu(socket)

    # Send A-ABORT instead of AC
    :ok = :gen_tcp.send(socket, <<0x07, 0x00, 4::32-big, 0x00, 0x00, 2, 0>>)
  end

  defp run_mock_server(socket, :unexpected) do
    # Read A-ASSOCIATE-RQ
    {:ok, _rq} = recv_full_pdu(socket)

    # Send a P-DATA PDU (unexpected during association negotiation)
    data = <<0x01, 0x03, 0xAA>>
    pdv_len = byte_size(data)
    pdv_payload = <<pdv_len::32-big, data::binary>>

    :ok =
      :gen_tcp.send(socket, <<0x04, 0x00, byte_size(pdv_payload)::32-big, pdv_payload::binary>>)
  end

  defp run_mock_server(socket, :accept_no_release) do
    # Read A-ASSOCIATE-RQ
    {:ok, _rq} = recv_full_pdu(socket)

    # Send A-ASSOCIATE-AC
    ac_pdu = build_associate_ac()
    :ok = :gen_tcp.send(socket, ac_pdu)

    # Just wait for the connection to close (don't send anything)
    _ = :gen_tcp.recv(socket, 0, 10_000)
  end

  defp run_mock_server(socket, :echo_pdata) do
    # Read A-ASSOCIATE-RQ
    {:ok, _rq} = recv_full_pdu(socket)

    # Send A-ASSOCIATE-AC
    ac_pdu = build_associate_ac()
    :ok = :gen_tcp.send(socket, ac_pdu)

    # Read P-DATA and echo it back
    {:ok, pdata} = recv_full_pdu(socket)
    :ok = :gen_tcp.send(socket, pdata)

    # Wait for release
    case recv_full_pdu(socket) do
      {:ok, _} ->
        :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)

      {:error, :closed} ->
        :ok
    end
  end

  defp run_mock_server(socket, {:send_after_accept, bytes}) do
    {:ok, _rq} = recv_full_pdu(socket)
    :ok = :gen_tcp.send(socket, build_associate_ac() <> bytes)
    _ = :gen_tcp.recv(socket, 0, 10_000)
  end

  defp run_mock_server(socket, {:roles, parent}) do
    {:ok, rq} = recv_full_pdu(socket)
    send(parent, {:associate_rq, rq})

    ct = "1.2.840.10008.5.1.4.1.1.2"
    role_item = <<0x54, 0x00, 29::16-big, 25::16-big, ct::binary, 0, 1>>

    contexts = [{1, 0}, {3, 0}, {5, 3}]
    :ok = :gen_tcp.send(socket, build_associate_ac(contexts, 16_384, role_item))
    reply_release(socket)
  end

  defp run_mock_server(socket, {:fragments, parent}) do
    {:ok, _rq} = recv_full_pdu(socket)
    :ok = :gen_tcp.send(socket, build_associate_ac([{1, 0}], 20, <<>>))
    send(parent, {:fragments, recv_until_last(socket, [])})
    reply_release(socket)
  end

  defp recv_until_last(socket, acc) do
    {:ok, pdu} = recv_full_pdu(socket)
    # PDUs must respect the 20-byte maximum advertised in the AC
    <<0x04, 0x00, length::32-big, _::binary>> = pdu
    true = length <= 20
    {:ok, {:p_data, [pdv]}, <<>>} = PDU.decode_pdu(pdu)
    acc = [pdv | acc]
    if pdv.is_last, do: Enum.reverse(acc), else: recv_until_last(socket, acc)
  end

  # A one-PDV P-DATA-TF PDU whose length field is `length`
  defp p_data_of_length(length) do
    data = :binary.copy(<<0>>, length - 6)
    <<0x04, 0x00, length::32-big, length - 4::32-big, 1, 0x02, data::binary>>
  end

  defp reply_release(socket) do
    case recv_full_pdu(socket) do
      {:ok, _} -> :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)
      {:error, :closed} -> :ok
    end
  end

  defp recv_full_pdu(socket) do
    case :gen_tcp.recv(socket, 6, 5_000) do
      {:ok, <<_type::8, _reserved::8, length::32-big>> = header} ->
        case :gen_tcp.recv(socket, length, 5_000) do
          {:ok, payload} -> {:ok, header <> payload}
          error -> error
        end

      {:error, :closed} ->
        {:error, :closed}

      error ->
        error
    end
  end

  defp build_associate_ac(contexts, max_pdu_length, extra_user_info) do
    ts_uid = @implicit_vr_le
    ts_item = <<0x40, 0x00, byte_size(ts_uid)::16-big, ts_uid::binary>>

    pc_items =
      for {id, result} <- contexts, into: <<>> do
        content = <<id, 0x00, result, 0x00, ts_item::binary>>
        <<0x21, 0x00, byte_size(content)::16-big, content::binary>>
      end

    user_info_content =
      <<0x51, 0x00, 4::16-big, max_pdu_length::32-big, extra_user_info::binary>>

    user_info = <<0x50, 0x00, byte_size(user_info_content)::16-big, user_info_content::binary>>

    payload =
      IO.iodata_to_binary([
        <<1::16-big, 0::16>>,
        String.pad_trailing("TEST_SCP", 16, " "),
        String.pad_trailing("TEST_SCU", 16, " "),
        <<0::256>>,
        pc_items,
        user_info
      ])

    <<0x02, 0x00, byte_size(payload)::32-big, payload::binary>>
  end

  defp build_associate_ac do
    called_ae = String.pad_trailing("TEST_SCP", 16, " ")
    calling_ae = String.pad_trailing("TEST_SCU", 16, " ")

    # Transfer syntax sub-item
    ts_uid = @implicit_vr_le
    ts_item = <<0x40, 0x00, byte_size(ts_uid)::16-big, ts_uid::binary>>

    # Presentation context (accepted, result=0)
    pc_content = <<1, 0x00, 0, 0x00, ts_item::binary>>
    pc_item = <<0x21, 0x00, byte_size(pc_content)::16-big, pc_content::binary>>

    # User information with max PDU length
    max_length_sub = <<0x51, 0x00, 4::16-big, 65_536::32-big>>
    user_info_content = max_length_sub
    user_info = <<0x50, 0x00, byte_size(user_info_content)::16-big, user_info_content::binary>>

    payload =
      IO.iodata_to_binary([
        <<1::16-big>>,
        <<0::16>>,
        called_ae,
        calling_ae,
        <<0::256>>,
        pc_item,
        user_info
      ])

    <<0x02, 0x00, byte_size(payload)::32-big, payload::binary>>
  end
end
