defmodule Dcmix.Network.CStoreTest do
  use ExUnit.Case

  alias Dcmix.DataSet
  alias Dcmix.Network.CStore

  @implicit_vr_le "1.2.840.10008.1.2"
  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"
  @sop_instance_uid "1.2.3.4.5.6.7.8.9.0"

  describe "send/3" do
    test "stores a DICOM file and returns success status" do
      file = build_test_dicom_file()
      {port, server_pid} = start_mock_cstore_server(0x0000)

      try do
        assert {:ok, 0x0000} =
                 CStore.send("127.0.0.1:#{port}", file,
                   calling_ae_title: "TEST_SCU",
                   called_ae_title: "TEST_SCP"
                 )
      after
        File.rm(file)
      end

      wait_for_server(server_pid)
    end

    test "returns the SCP's non-success status verbatim" do
      file = build_test_dicom_file()
      {port, server_pid} = start_mock_cstore_server(0xA700)

      try do
        assert {:ok, 0xA700} =
                 CStore.send("127.0.0.1:#{port}", file,
                   calling_ae_title: "TEST_SCU",
                   called_ae_title: "TEST_SCP"
                 )
      after
        File.rm(file)
      end

      wait_for_server(server_pid)
    end

    test "returns error when file does not exist" do
      assert {:error, {:file_error, :enoent}} =
               CStore.send("127.0.0.1:1", "/nonexistent/missing.dcm")
    end

    test "returns error when file has no SOP Class UID" do
      file = build_test_dicom_file(sop_class_uid: nil)

      try do
        assert {:error, {:missing_uid, :sop_class_uid}} =
                 CStore.send("127.0.0.1:1", file)
      after
        File.rm(file)
      end
    end

    test "returns error when file has no SOP Instance UID" do
      file = build_test_dicom_file(sop_instance_uid: nil)

      try do
        assert {:error, {:missing_uid, :sop_instance_uid}} =
                 CStore.send("127.0.0.1:1", file)
      after
        File.rm(file)
      end
    end

    test "returns connection error for unreachable server" do
      file = build_test_dicom_file()

      try do
        assert {:error, {:connection_failed, _}} =
                 CStore.send("127.0.0.1:1", file,
                   calling_ae_title: "TEST",
                   called_ae_title: "MOCK"
                 )
      after
        File.rm(file)
      end
    end

    test "returns error when the association is aborted mid-response" do
      file = build_test_dicom_file()
      {port, server_pid} = start_mock_cstore_abort_server()

      try do
        assert {:error, :association_aborted} =
                 CStore.send("127.0.0.1:#{port}", file,
                   calling_ae_title: "TEST_SCU",
                   called_ae_title: "TEST_SCP"
                 )
      after
        File.rm(file)
      end

      wait_for_server(server_pid)
    end

    test "returns error when SCP rejects the presentation context" do
      file = build_test_dicom_file()
      {port, server_pid} = start_mock_cstore_reject_context_server()

      try do
        assert {:error, :no_accepted_presentation_context} =
                 CStore.send("127.0.0.1:#{port}", file,
                   calling_ae_title: "TEST_SCU",
                   called_ae_title: "TEST_SCP"
                 )
      after
        File.rm(file)
      end

      wait_for_server(server_pid)
    end

    @tag capture_log: true
    test "runs with verbose logging enabled" do
      file = build_test_dicom_file()
      {port, server_pid} = start_mock_cstore_server(0x0000)

      try do
        assert {:ok, 0x0000} =
                 CStore.send("127.0.0.1:#{port}", file,
                   calling_ae_title: "TEST_SCU",
                   called_ae_title: "TEST_SCP",
                   verbose: true
                 )
      after
        File.rm(file)
      end

      wait_for_server(server_pid)
    end

    test "uses a custom message ID when provided" do
      file = build_test_dicom_file()
      {port, server_pid, ref} = start_mock_cstore_capture_server(0x0000)

      try do
        assert {:ok, 0x0000} =
                 CStore.send("127.0.0.1:#{port}", file,
                   calling_ae_title: "TEST_SCU",
                   called_ae_title: "TEST_SCP",
                   message_id: 42
                 )
      after
        File.rm(file)
      end

      assert_receive {^ref, :command, command_bytes}, 5_000

      # Message ID tag (0000,0110) US value 42
      pattern = <<0x0000::16-little, 0x0110::16-little, 2::32-little, 42::16-little>>
      assert :binary.match(command_bytes, pattern) != :nomatch

      wait_for_server(server_pid)
    end
  end

  # ===========================================================================
  # Test DICOM file builder
  # ===========================================================================

  defp build_test_dicom_file(opts \\ []) do
    sop_class_uid = Keyword.get(opts, :sop_class_uid, @ct_image_storage)
    sop_instance_uid = Keyword.get(opts, :sop_instance_uid, @sop_instance_uid)

    ds = DataSet.put_element(DataSet.new(), {0x0010, 0x0010}, :PN, "Test^Patient")

    ds =
      if sop_class_uid do
        DataSet.put_element(ds, {0x0008, 0x0016}, :UI, sop_class_uid)
      else
        ds
      end

    ds =
      if sop_instance_uid do
        DataSet.put_element(ds, {0x0008, 0x0018}, :UI, sop_instance_uid)
      else
        ds
      end

    path =
      Path.join(
        System.tmp_dir!(),
        "cstore_test_#{System.unique_integer([:positive])}.dcm"
      )

    :ok = Dcmix.write_file(ds, path, transfer_syntax: @implicit_vr_le)
    path
  end

  # ===========================================================================
  # Mock DICOM C-STORE SCP servers
  # ===========================================================================

  defp start_mock_cstore_server(status_code) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          run_cstore_server(socket, status_code)
          :gen_tcp.close(socket)
        after
          :gen_tcp.close(listen)
          send(parent, {:server_done, self()})
        end
      end)

    {port, pid}
  end

  defp start_mock_cstore_capture_server(status_code) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()
    ref = make_ref()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          run_cstore_capture_server(socket, status_code, parent, ref)
          :gen_tcp.close(socket)
        after
          :gen_tcp.close(listen)
          send(parent, {:server_done, self()})
        end
      end)

    {port, pid, ref}
  end

  defp start_mock_cstore_abort_server do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          {:ok, _rq} = recv_full_pdu(socket)
          :ok = :gen_tcp.send(socket, build_associate_ac())
          {:ok, _cmd} = recv_full_pdu(socket)
          {:ok, _data} = recv_full_pdu(socket)
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

  defp start_mock_cstore_reject_context_server do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          {:ok, _rq} = recv_full_pdu(socket)
          :ok = :gen_tcp.send(socket, build_associate_ac_all_rejected())
          _ = :gen_tcp.recv(socket, 0, 2_000)
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

  defp run_cstore_server(socket, status_code) do
    {:ok, _rq} = recv_full_pdu(socket)
    :ok = :gen_tcp.send(socket, build_associate_ac())
    {:ok, _command_pdu} = recv_full_pdu(socket)
    {:ok, _data_pdu} = recv_full_pdu(socket)
    :ok = :gen_tcp.send(socket, build_cstore_response(status_code))

    case recv_full_pdu(socket) do
      {:ok, _release_rq} ->
        :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)

      {:error, :closed} ->
        :ok
    end
  end

  defp run_cstore_capture_server(socket, status_code, parent, ref) do
    {:ok, _rq} = recv_full_pdu(socket)
    :ok = :gen_tcp.send(socket, build_associate_ac())

    {:ok, command_pdu} = recv_full_pdu(socket)
    send(parent, {ref, :command, extract_pdv_data(command_pdu)})

    {:ok, _data_pdu} = recv_full_pdu(socket)
    :ok = :gen_tcp.send(socket, build_cstore_response(status_code))

    case recv_full_pdu(socket) do
      {:ok, _release_rq} ->
        :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)

      {:error, :closed} ->
        :ok
    end
  end

  # Pull the inner PDV payload bytes (skipping PDU header, PDV length, and
  # PDV control header) so tests can pattern-match the command dataset.
  defp extract_pdv_data(
         <<0x04, 0x00, _pdu_length::32-big, _pdv_length::32-big, _context_id::8, _control::8,
           data::binary>>
       ),
       do: data

  defp extract_pdv_data(_), do: <<>>

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

  # ===========================================================================
  # PDU/PDV builders for the mock SCP
  # ===========================================================================

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

  defp build_associate_ac_all_rejected do
    called_ae = String.pad_trailing("TEST_SCP", 16, " ")
    calling_ae = String.pad_trailing("TEST_SCU", 16, " ")

    ts_uid = @implicit_vr_le
    ts_item = <<0x40, 0x00, byte_size(ts_uid)::16-big, ts_uid::binary>>

    # result=1 (user-rejection)
    pc_content = <<1, 0x00, 1, 0x00, ts_item::binary>>
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

  # C-STORE-RSP command (Implicit VR LE) wrapped in a P-DATA-TF PDU.
  defp build_cstore_response(status_code) do
    command_binary = build_cstore_rsp_command(status_code)

    pdv_len = 1 + 1 + byte_size(command_binary)
    pdu_payload = <<pdv_len::32-big, 1::8, 0x03::8, command_binary::binary>>
    <<0x04, 0x00, byte_size(pdu_payload)::32-big, pdu_payload::binary>>
  end

  defp build_cstore_rsp_command(status) do
    uid = @ct_image_storage
    padded_uid = if rem(byte_size(uid), 2) == 1, do: uid <> <<0>>, else: uid

    instance = @sop_instance_uid

    padded_instance =
      if rem(byte_size(instance), 2) == 1, do: instance <> <<0>>, else: instance

    elements =
      IO.iodata_to_binary([
        # Affected SOP Class UID (0000,0002)
        <<0x0000::16-little, 0x0002::16-little, byte_size(padded_uid)::32-little,
          padded_uid::binary>>,
        # Command Field (0000,0100) = 0x8001 (C-STORE-RSP)
        <<0x0000::16-little, 0x0100::16-little, 2::32-little, 0x8001::16-little>>,
        # Message ID Being Responded To (0000,0120)
        <<0x0000::16-little, 0x0120::16-little, 2::32-little, 1::16-little>>,
        # Command Data Set Type (0000,0800) = 0x0101 (no dataset)
        <<0x0000::16-little, 0x0800::16-little, 2::32-little, 0x0101::16-little>>,
        # Status (0000,0900)
        <<0x0000::16-little, 0x0900::16-little, 2::32-little, status::16-little>>,
        # Affected SOP Instance UID (0000,1000)
        <<0x0000::16-little, 0x1000::16-little, byte_size(padded_instance)::32-little,
          padded_instance::binary>>
      ])

    group_length =
      <<0x0000::16-little, 0x0000::16-little, 4::32-little, byte_size(elements)::32-little>>

    group_length <> elements
  end
end
