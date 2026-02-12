defmodule Dcmix.Network.CFindTest do
  use ExUnit.Case

  alias Dcmix.{DataSet, Writer}
  alias Dcmix.Network.{CFind, Query}

  @implicit_vr_le "1.2.840.10008.1.2"

  describe "query/3" do
    test "returns empty results when server responds with immediate success" do
      {port, server_pid} = start_mock_cfind_server([])
      {:ok, query_ds} = Query.parse_terms(["PatientName"])

      assert {:ok, datasets} =
               CFind.query("127.0.0.1:#{port}", query_ds,
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP"
               )

      assert datasets == []

      wait_for_server(server_pid)
    end

    test "returns matched studies as DataSets" do
      # Build response datasets (Implicit VR LE)
      response_datasets = [
        build_response_dataset("Doe^John", "12345", "20250101"),
        build_response_dataset("Smith^Jane", "67890", "20250202")
      ]

      {port, server_pid} = start_mock_cfind_server(response_datasets)
      {:ok, query_ds} = Query.parse_terms(["PatientName", "PatientID", "StudyDate"])

      assert {:ok, datasets} =
               CFind.query("127.0.0.1:#{port}", query_ds,
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP"
               )

      assert length(datasets) == 2

      # Verify the DataSets contain expected data
      [ds1, ds2] = datasets

      assert %DataSet{} = ds1
      assert %DataSet{} = ds2

      # Check PatientID values
      assert DataSet.get_string(ds1, {0x0010, 0x0020}) == "12345"
      assert DataSet.get_string(ds2, {0x0010, 0x0020}) == "67890"

      wait_for_server(server_pid)
    end

    test "returns error for connection failure" do
      {:ok, query_ds} = Query.parse_terms(["PatientName"])

      assert {:error, {:connection_failed, _}} =
               CFind.query("127.0.0.1:1", query_ds,
                 calling_ae_title: "TEST",
                 called_ae_title: "MOCK"
               )
    end

    test "handles single result" do
      response_datasets = [
        build_response_dataset("Solo^Patient", "11111", "20250301")
      ]

      {port, server_pid} = start_mock_cfind_server(response_datasets)
      {:ok, query_ds} = Query.parse_terms(["PatientName", "StudyDate=20250301"])

      assert {:ok, datasets} =
               CFind.query("127.0.0.1:#{port}", query_ds,
                 calling_ae_title: "SCU",
                 called_ae_title: "SCP"
               )

      assert length(datasets) == 1
      [ds] = datasets
      assert DataSet.get_string(ds, {0x0010, 0x0020}) == "11111"

      wait_for_server(server_pid)
    end

    test "returns error when server sends failure status" do
      {port, server_pid} = start_mock_cfind_failure_server(0xA700)
      {:ok, query_ds} = Query.parse_terms(["PatientName"])

      assert {:error, {:cfind_failed, 0xA700}} =
               CFind.query("127.0.0.1:#{port}", query_ds,
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP"
               )

      wait_for_server(server_pid)
    end

    test "returns error when server sends abort during response" do
      {port, server_pid} = start_mock_cfind_abort_server()
      {:ok, query_ds} = Query.parse_terms(["PatientName"])

      assert {:error, :association_aborted} =
               CFind.query("127.0.0.1:#{port}", query_ds,
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP"
               )

      wait_for_server(server_pid)
    end

    @tag capture_log: true
    test "runs with verbose logging enabled" do
      response_datasets = [
        build_response_dataset("Verbose^Test", "99999", "20250601")
      ]

      {port, server_pid} = start_mock_cfind_server(response_datasets)
      {:ok, query_ds} = Query.parse_terms(["PatientName"])

      assert {:ok, datasets} =
               CFind.query("127.0.0.1:#{port}", query_ds,
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP",
                 verbose: true
               )

      assert length(datasets) == 1
      wait_for_server(server_pid)
    end

    test "handles response with data in same PDU as command" do
      {port, server_pid} = start_mock_cfind_inline_data_server()
      {:ok, query_ds} = Query.parse_terms(["PatientName"])

      assert {:ok, datasets} =
               CFind.query("127.0.0.1:#{port}", query_ds,
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP"
               )

      assert length(datasets) == 1
      wait_for_server(server_pid)
    end

    test "returns error when server sends unexpected release" do
      {port, server_pid} = start_mock_cfind_release_server()
      {:ok, query_ds} = Query.parse_terms(["PatientName"])

      assert {:error, :unexpected_release} =
               CFind.query("127.0.0.1:#{port}", query_ds,
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP"
               )

      wait_for_server(server_pid)
    end
  end

  # ===========================================================================
  # Mock DICOM C-FIND Server
  # ===========================================================================

  defp start_mock_cfind_server(response_datasets) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          run_cfind_server(socket, response_datasets)
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

  defp run_cfind_server(socket, response_datasets) do
    # 1. Read A-ASSOCIATE-RQ, send A-ASSOCIATE-AC
    {:ok, _rq} = recv_full_pdu(socket)
    :ok = :gen_tcp.send(socket, build_associate_ac())

    # 2. Read C-FIND command P-DATA
    {:ok, _cmd_pdata} = recv_full_pdu(socket)

    # 3. Read C-FIND query P-DATA
    {:ok, _query_pdata} = recv_full_pdu(socket)

    # 4. Send responses: pending for each result, then success
    Enum.each(response_datasets, fn dataset_binary ->
      pending_response = build_cfind_pending_response(dataset_binary)
      :ok = :gen_tcp.send(socket, pending_response)
    end)

    # 5. Send final success response
    success_response = build_cfind_success_response()
    :ok = :gen_tcp.send(socket, success_response)

    # 6. Handle release
    case recv_full_pdu(socket) do
      {:ok, _} ->
        :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)

      {:error, :closed} ->
        :ok
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

  # Build an A-ASSOCIATE-AC response
  defp build_associate_ac do
    called_ae = String.pad_trailing("TEST_SCP", 16, " ")
    calling_ae = String.pad_trailing("TEST_SCU", 16, " ")

    ts_uid = @implicit_vr_le
    ts_item = <<0x40, 0x00, byte_size(ts_uid)::16-big, ts_uid::binary>>

    pc_content = <<1, 0x00, 0, 0x00, ts_item::binary>>
    pc_item = <<0x21, 0x00, byte_size(pc_content)::16-big, pc_content::binary>>

    max_length_sub = <<0x51, 0x00, 4::16-big, 65_536::32-big>>
    user_info = <<0x50, 0x00, byte_size(max_length_sub)::16-big, max_length_sub::binary>>

    payload =
      IO.iodata_to_binary([
        <<1::16-big, 0::16>>,
        called_ae,
        calling_ae,
        <<0::256>>,
        pc_item,
        user_info
      ])

    <<0x02, 0x00, byte_size(payload)::32-big, payload::binary>>
  end

  # Build a C-FIND pending response (status 0xFF00) with data in a separate PDU
  defp build_cfind_pending_response(dataset_binary) do
    # Command response with status=pending
    command_binary = build_cfind_rsp_command(0xFF00)

    # Command P-DATA PDU
    cmd_pdv_len = 1 + 1 + byte_size(command_binary)
    cmd_pdu_payload = <<cmd_pdv_len::32-big, 1::8, 0x03::8, command_binary::binary>>
    cmd_pdu = <<0x04, 0x00, byte_size(cmd_pdu_payload)::32-big, cmd_pdu_payload::binary>>

    # Data P-DATA PDU (separate PDU)
    data_pdv_len = 1 + 1 + byte_size(dataset_binary)
    data_pdu_payload = <<data_pdv_len::32-big, 1::8, 0x02::8, dataset_binary::binary>>
    data_pdu = <<0x04, 0x00, byte_size(data_pdu_payload)::32-big, data_pdu_payload::binary>>

    cmd_pdu <> data_pdu
  end

  # Build a C-FIND success response (status 0x0000, no data)
  defp build_cfind_success_response do
    command_binary = build_cfind_rsp_command(0x0000)

    pdv_len = 1 + 1 + byte_size(command_binary)
    pdu_payload = <<pdv_len::32-big, 1::8, 0x03::8, command_binary::binary>>
    <<0x04, 0x00, byte_size(pdu_payload)::32-big, pdu_payload::binary>>
  end

  # Build a C-FIND-RSP command dataset as Implicit VR LE binary
  defp build_cfind_rsp_command(status) do
    # SOP Class UID (null-padded to even length)
    uid = "1.2.840.10008.5.1.4.1.2.2.1"
    padded_uid = if rem(byte_size(uid), 2) == 1, do: uid <> <<0>>, else: uid

    elements =
      IO.iodata_to_binary([
        # Affected SOP Class UID (0000,0002)
        <<0x0000::16-little, 0x0002::16-little, byte_size(padded_uid)::32-little,
          padded_uid::binary>>,
        # Command Field (0000,0100) = 0x8020 (C-FIND-RSP)
        <<0x0000::16-little, 0x0100::16-little, 2::32-little, 0x8020::16-little>>,
        # Status (0000,0900)
        <<0x0000::16-little, 0x0900::16-little, 2::32-little, status::16-little>>
      ])

    # Group length
    group_length =
      <<0x0000::16-little, 0x0000::16-little, 4::32-little, byte_size(elements)::32-little>>

    group_length <> elements
  end

  # Mock server that sends a failure status immediately
  defp start_mock_cfind_failure_server(status_code) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          {:ok, _rq} = recv_full_pdu(socket)
          :ok = :gen_tcp.send(socket, build_associate_ac())
          {:ok, _cmd_pdata} = recv_full_pdu(socket)
          {:ok, _query_pdata} = recv_full_pdu(socket)

          # Send failure status response
          command_binary = build_cfind_rsp_command(status_code)
          pdv_len = 1 + 1 + byte_size(command_binary)
          pdu_payload = <<pdv_len::32-big, 1::8, 0x03::8, command_binary::binary>>

          :ok =
            :gen_tcp.send(
              socket,
              <<0x04, 0x00, byte_size(pdu_payload)::32-big, pdu_payload::binary>>
            )

          :gen_tcp.close(socket)
        after
          :gen_tcp.close(listen)
          send(parent, {:server_done, self()})
        end
      end)

    {port, pid}
  end

  # Mock server that sends an abort during response
  defp start_mock_cfind_abort_server do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          {:ok, _rq} = recv_full_pdu(socket)
          :ok = :gen_tcp.send(socket, build_associate_ac())
          {:ok, _cmd_pdata} = recv_full_pdu(socket)
          {:ok, _query_pdata} = recv_full_pdu(socket)

          # Send abort instead of C-FIND response
          abort = <<0x07, 0x00, 4::32-big, 0x00, 0x00, 2, 0>>
          :ok = :gen_tcp.send(socket, abort)
          :gen_tcp.close(socket)
        after
          :gen_tcp.close(listen)
          send(parent, {:server_done, self()})
        end
      end)

    {port, pid}
  end

  # Mock server that sends data inline (in same P-DATA PDU as command)
  defp start_mock_cfind_inline_data_server do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          {:ok, _rq} = recv_full_pdu(socket)
          :ok = :gen_tcp.send(socket, build_associate_ac())
          {:ok, _cmd_pdata} = recv_full_pdu(socket)
          {:ok, _query_pdata} = recv_full_pdu(socket)

          # Send pending response with command and data in same P-DATA PDU
          dataset_binary = build_response_dataset("Inline^Data", "55555", "20250401")
          command_binary = build_cfind_rsp_command(0xFF00)

          cmd_pdv_len = 1 + 1 + byte_size(command_binary)
          data_pdv_len = 1 + 1 + byte_size(dataset_binary)

          pdu_payload =
            IO.iodata_to_binary([
              <<cmd_pdv_len::32-big, 1::8, 0x03::8, command_binary::binary>>,
              <<data_pdv_len::32-big, 1::8, 0x02::8, dataset_binary::binary>>
            ])

          :ok =
            :gen_tcp.send(
              socket,
              <<0x04, 0x00, byte_size(pdu_payload)::32-big, pdu_payload::binary>>
            )

          # Send success
          success_response = build_cfind_success_response()
          :ok = :gen_tcp.send(socket, success_response)

          # Handle release
          case recv_full_pdu(socket) do
            {:ok, _} ->
              :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)

            {:error, :closed} ->
              :ok
          end

          :gen_tcp.close(socket)
        after
          :gen_tcp.close(listen)
          send(parent, {:server_done, self()})
        end
      end)

    {port, pid}
  end

  # Mock server that sends an unexpected release request during C-FIND
  defp start_mock_cfind_release_server do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          {:ok, _rq} = recv_full_pdu(socket)
          :ok = :gen_tcp.send(socket, build_associate_ac())
          {:ok, _cmd_pdata} = recv_full_pdu(socket)
          {:ok, _query_pdata} = recv_full_pdu(socket)

          # Send release-rq instead of C-FIND response
          :ok = :gen_tcp.send(socket, <<0x05, 0x00, 4::32-big, 0::32>>)
          :gen_tcp.close(socket)
        after
          :gen_tcp.close(listen)
          send(parent, {:server_done, self()})
        end
      end)

    {port, pid}
  end

  # Build a response dataset as Implicit VR Little Endian binary
  defp build_response_dataset(patient_name, patient_id, study_date) do
    ds =
      DataSet.new()
      |> DataSet.put_element({0x0010, 0x0010}, :PN, patient_name)
      |> DataSet.put_element({0x0010, 0x0020}, :LO, patient_id)
      |> DataSet.put_element({0x0008, 0x0020}, :DA, study_date)

    Writer.ImplicitVR.encode(ds)
  end
end
