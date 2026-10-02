defmodule Dcmix.Network.CGetTest do
  use ExUnit.Case

  alias Dcmix.{DataSet, Parser, Writer}
  alias Dcmix.Network.{CGet, DIMSE, PDU}
  alias Dcmix.Network.CGet.Result

  @implicit_vr_le "1.2.840.10008.1.2"
  @explicit_vr_le "1.2.840.10008.1.2.1"
  @patient_root_get "1.2.840.10008.5.1.4.1.2.1.3"
  @study_root_get "1.2.840.10008.5.1.4.1.2.2.3"
  @ct_storage "1.2.840.10008.5.1.4.1.1.2"
  @mr_storage "1.2.840.10008.5.1.4.1.1.4"

  @mr_fixture "test/fixtures/nema_mr_diffusion_128x128.dcm"

  @default_accept %{
    @patient_root_get => @explicit_vr_le,
    @study_root_get => @explicit_vr_le,
    @ct_storage => @implicit_vr_le,
    @mr_storage => @explicit_vr_le
  }

  setup do
    dir = Path.join(System.tmp_dir!(), "dcmix_cget_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  describe "get/3 - bit-preserving storage" do
    test "stores sub-operations byte-for-byte with generated file meta", %{dir: dir} do
      ct_dataset = ct_dataset("1.2.3.100")
      {mr_ts, mr_dataset} = split_part10(File.read!(@mr_fixture))
      {:ok, mr} = Parser.parse(File.read!(@mr_fixture))
      mr_uid = DataSet.get_string(mr, {0x0008, 0x0018})
      assert mr_ts == @explicit_vr_le

      {port, pid} =
        start_scp(fn socket, ctx ->
          {get_ctx, get_rq} = recv_command(socket)
          identifier = recv_dataset(socket)
          send_parent({:get_rq, get_ctx, get_rq, identifier})

          send_command(socket, get_ctx, cget_rsp(0xFF00, remaining: 2, completed: 0))

          # Command and data set in a single P-DATA PDU
          :ok =
            :gen_tcp.send(
              socket,
              pdata([
                {ctx[@ct_storage], 0x03, cstore_rq(@ct_storage, "1.2.3.100", 7)},
                {ctx[@ct_storage], 0x02, ct_dataset}
              ])
            )

          send_parent({:store_rsp, recv_command(socket)})
          send_command(socket, get_ctx, cget_rsp(0xFF00, remaining: 1, completed: 1))

          # Command split over two PDVs, data set over several PDUs
          <<cmd_a::binary-size(20), cmd_b::binary>> = cstore_rq(@mr_storage, mr_uid, 8)
          :ok = :gen_tcp.send(socket, pdata([{ctx[@mr_storage], 0x01, cmd_a}]))
          :ok = :gen_tcp.send(socket, pdata([{ctx[@mr_storage], 0x03, cmd_b}]))
          send_data(socket, ctx[@mr_storage], mr_dataset, 10_000)

          send_parent({:store_rsp, recv_command(socket)})
          send_command(socket, get_ctx, cget_rsp(0x0000, completed: 2, failed: 0, warning: 0))
          handle_release(socket)
        end)

      query = study_identifier("1.2.3")

      assert {:ok, %Result{} = result} =
               CGet.get("127.0.0.1:#{port}", query,
                 calling_ae_title: "TEST_SCU",
                 called_ae_title: "TEST_SCP",
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage, @mr_storage]
               )

      assert result.status == 0x0000
      assert result.completed == 2
      assert result.failed == 0
      assert result.warning == 0
      assert result.files == [Path.join(dir, "1.2.3.100"), Path.join(dir, mr_uid)]

      assert_received {:get_rq, 1, get_rq, identifier}
      assert get_rq.command_field == 0x0010
      assert get_rq.affected_sop_class_uid == @patient_root_get
      assert get_rq.message_id == 1
      assert {:ok, parsed_identifier, _} = Parser.ExplicitVR.parse(identifier)
      assert DataSet.get_string(parsed_identifier, {0x0020, 0x000D}) == "1.2.3"

      assert_received {:store_rsp, {_ctx, ct_rsp}}
      assert ct_rsp.command_field == 0x8001
      assert ct_rsp.status == 0x0000
      assert ct_rsp.message_id_being_responded_to == 7
      assert ct_rsp.affected_sop_instance_uid == "1.2.3.100"
      assert_received {:store_rsp, {_ctx, %{status: 0x0000, message_id_being_responded_to: 8}}}

      [ct_path, mr_path] = result.files
      refute Enum.any?(File.ls!(dir), &String.ends_with?(&1, ".part"))
      assert stored_dataset(ct_path) == ct_dataset
      assert stored_dataset(mr_path) == mr_dataset

      assert {:ok, meta} = Parser.parse_file_meta_only(ct_path)
      assert DataSet.get_string(meta, {0x0002, 0x0002}) == @ct_storage
      assert DataSet.get_string(meta, {0x0002, 0x0003}) == "1.2.3.100"
      assert DataSet.get_string(meta, {0x0002, 0x0010}) == @implicit_vr_le
      assert DataSet.get_string(meta, {0x0002, 0x0016}) == "TEST_SCU"

      assert {:ok, stored_mr} = Parser.parse_file(mr_path)
      assert DataSet.get_string(stored_mr, {0x0008, 0x0018}) == mr_uid

      assert_received {:associate_rq, proposed}
      assert hd(proposed.contexts).abstract_syntax == @patient_root_get

      assert Enum.sort(proposed.roles) == [
               {@ct_storage, 0, 1},
               {@mr_storage, 0, 1}
             ]

      wait_for_server(pid)
    end

    test "creates a missing output directory", %{dir: dir} do
      nested = Path.join(dir, "a/b")
      {port, pid} = start_scp(single_store_script(@ct_storage, "1.2.3.5"))

      assert {:ok, %Result{files: [path]}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: nested,
                 storage_sop_classes: [@ct_storage]
               )

      assert path == Path.join(nested, "1.2.3.5")
      assert File.exists?(path)
      wait_for_server(pid)
    end

    test "sanitizes the SOP Instance UID used as the file name", %{dir: dir} do
      {port, pid} = start_scp(single_store_script(@ct_storage, "../x/y"))

      assert {:ok, %Result{files: [path]}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert path == Path.join(dir, ".._x_y")
      assert File.ls!(dir) == [".._x_y"]
      wait_for_server(pid)
    end

    test "replaces characters unsafe on Windows file systems", %{dir: dir} do
      {port, pid} = start_scp(single_store_script(@ct_storage, "1.2:3 4"))

      assert {:ok, %Result{files: [path]}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert path == Path.join(dir, "1.2_3_4")
      wait_for_server(pid)
    end

    test "refuses Windows reserved device names and continues", %{dir: dir} do
      uids = ["CON.1.2", "aux", "lpt9.5", "Com1", "COM10.1", "CONSOLE"]

      {port, pid} =
        start_scp(fn socket, ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)

          for {uid, n} <- Enum.with_index(uids, 2) do
            send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, uid, n))
            send_data(socket, ctx[@ct_storage], ct_dataset(uid), 10_000)
            send_parent({:store_rsp, uid, recv_command(socket)})
          end

          send_command(socket, get_ctx, cget_rsp(0xB000, completed: 2, failed: 4))
          handle_release(socket)
        end)

      assert {:ok, %Result{files: files}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      statuses =
        for uid <- uids do
          assert_received {:store_rsp, ^uid, {_ctx, %{status: status}}}
          {uid, status}
        end

      assert statuses == [
               {"CON.1.2", 0xC000},
               {"aux", 0xC000},
               {"lpt9.5", 0xC000},
               {"Com1", 0xC000},
               {"COM10.1", 0x0000},
               {"CONSOLE", 0x0000}
             ]

      assert files == [Path.join(dir, "COM10.1"), Path.join(dir, "CONSOLE")]
      wait_for_server(pid)
    end

    test "refuses a file name ending in a dot and continues", %{dir: dir} do
      {port, pid} = start_scp(single_store_script(@ct_storage, "1.2.3."))

      assert {:ok, %Result{status: 0x0000, files: []}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert_received {:store_rsp, {_ctx, %{status: 0xC000}}}
      assert File.ls!(dir) == []
      wait_for_server(pid)
    end

    test "refuses a SOP Instance UID that cannot be a file name", %{dir: dir} do
      {port, pid} = start_scp(single_store_script(@ct_storage, ".."))

      assert {:ok, %Result{files: []}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert_received {:store_rsp, {_ctx, %{status: 0xC000}}}
      wait_for_server(pid)
    end

    test "answers Out of Resources when the file cannot be created", %{dir: dir} do
      File.mkdir_p!(dir)
      File.chmod!(dir, 0o500)
      on_exit(fn -> File.chmod(dir, 0o700) end)

      {port, pid} = start_scp(single_store_script(@ct_storage, "1.2.3.6"))

      assert {:ok, %Result{files: []}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert_received {:store_rsp, {_ctx, %{status: 0xA700}}}
      wait_for_server(pid)
    end

    test "returns an error when the output directory cannot be created", %{dir: dir} do
      File.mkdir_p!(dir)
      file = Path.join(dir, "file")
      File.write!(file, "")

      assert {:error, {:output_directory_error, _}} =
               CGet.get("127.0.0.1:1", study_identifier("1.2.3"),
                 output_directory: Path.join(file, "sub")
               )
    end
  end

  describe "get/3 - temporary .part files" do
    test "a repeated SOP Instance UID replaces the file and is listed once", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)

          for {message_id, patient} <- [{2, "FIRST"}, {3, "SECOND"}] do
            send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.20", message_id))
            send_data(socket, ctx[@ct_storage], ct_dataset("1.2.3.20", patient), 10_000)
            send_parent({:store_rsp, recv_command(socket)})
          end

          send_command(socket, get_ctx, cget_rsp(0x0000, completed: 2))
          handle_release(socket)
        end)

      assert {:ok, %Result{files: [path]}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert stored_dataset(path) == ct_dataset("1.2.3.20", "SECOND")
      assert File.ls!(dir) == ["1.2.3.20"]
      wait_for_server(pid)
    end

    test "a repeat that fails to open leaves the earlier copy intact", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)

          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.21", 2))
          send_data(socket, ctx[@ct_storage], ct_dataset("1.2.3.21", "FIRST"), 10_000)
          send_parent({:store_rsp, recv_command(socket)})

          # Block the second .part file so it cannot be created
          File.mkdir_p!(Path.join(dir, "1.2.3.21.part/x"))

          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.21", 3))
          send_data(socket, ctx[@ct_storage], ct_dataset("1.2.3.21", "SECOND"), 10_000)
          send_parent({:store_rsp, recv_command(socket)})

          send_command(socket, get_ctx, cget_rsp(0xB000, completed: 1, failed: 1))
          handle_release(socket)
        end)

      assert {:ok, %Result{files: [path]}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert_received {:store_rsp, {_ctx, %{status: 0x0000}}}
      assert_received {:store_rsp, {_ctx, %{status: 0xA700}}}
      assert stored_dataset(path) == ct_dataset("1.2.3.21", "FIRST")
      wait_for_server(pid)
    end

    test "an aborted repeat removes only its .part file", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          {_get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)

          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.22", 2))
          send_data(socket, ctx[@ct_storage], ct_dataset("1.2.3.22", "FIRST"), 10_000)
          _ = recv_command(socket)

          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.22", 3))
          :ok = :gen_tcp.send(socket, pdata([{ctx[@ct_storage], 0x00, "partial"}]))
          :ok = :gen_tcp.send(socket, PDU.encode_abort(2, 0))
        end)

      assert {:error, :association_aborted} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert File.ls!(dir) == ["1.2.3.22"]
      assert stored_dataset(Path.join(dir, "1.2.3.22")) == ct_dataset("1.2.3.22", "FIRST")
      wait_for_server(pid)
    end

    test "answers Out of Resources when the final name cannot be replaced", %{dir: dir} do
      # A non-empty directory at the final name makes the rename fail
      File.mkdir_p!(Path.join(dir, "1.2.3.23/x"))
      {port, pid} = start_scp(single_store_script(@ct_storage, "1.2.3.23"))

      assert {:ok, %Result{files: []}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert_received {:store_rsp, {_ctx, %{status: 0xA700}}}
      assert File.ls!(dir) == ["1.2.3.23"]
      wait_for_server(pid)
    end
  end

  describe "get/3 - ignore storage mode" do
    test "discards data sets and still answers success", %{dir: dir} do
      {port, pid} = start_scp(single_store_script(@ct_storage, "1.2.3.7"))

      assert {:ok, %Result{status: 0x0000, files: []}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_mode: :ignore,
                 storage_sop_classes: [@ct_storage]
               )

      assert_received {:store_rsp, {_ctx, %{status: 0x0000}}}
      refute File.exists?(dir)
      wait_for_server(pid)
    end
  end

  describe "get/3 - sub-operation outcomes" do
    test "answers a C-STORE-RQ without a data set at once and continues", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)

          no_dataset =
            command([
              {0x0002, @ct_storage},
              {0x0100, 0x0001},
              {0x0110, 4},
              {0x0800, 0x0101},
              {0x1000, "1.2.3.24"}
            ])

          send_command(socket, ctx[@ct_storage], no_dataset)
          send_parent({:store_rsp, recv_command(socket)})
          send_command(socket, get_ctx, cget_rsp(0xB000, completed: 0, failed: 1))
          handle_release(socket)
        end)

      assert {:ok, %Result{status: 0xB000, failed: 1, files: []}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert_received {:store_rsp, {_ctx, %{status: 0xC000, message_id_being_responded_to: 4}}}
      wait_for_server(pid)
    end

    test "refuses a C-STORE on a non-storage context and continues", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)

          # Sent on the GET context, which is not a storage context
          send_command(socket, get_ctx, cstore_rq(@ct_storage, "1.2.3.8", 3))
          send_data(socket, get_ctx, ct_dataset("1.2.3.8"), 10_000)
          send_parent({:store_rsp, recv_command(socket)})

          send_command(socket, get_ctx, cget_rsp(0xB000, completed: 0, failed: 1, warning: 0))
          handle_release(socket)
        end)

      assert {:ok, %Result{status: 0xB000, completed: 0, failed: 1, files: []}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert_received {:store_rsp, {1, %{status: 0x0122, message_id_being_responded_to: 3}}}
      wait_for_server(pid)
    end

    test "returns a final failure response with its counts and identifier", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)

          send_command(socket, get_ctx, cget_rsp(0xFF00, remaining: 3, completed: 1))

          send_command(
            socket,
            get_ctx,
            cget_rsp(0xA702, [completed: 1, failed: 2, warning: 1], true)
          )

          failed_list =
            DataSet.new()
            |> DataSet.put_element({0x0008, 0x0058}, :UI, "1.2.3.9\\1.2.3.10")
            |> Writer.ExplicitVR.encode()

          send_data(socket, get_ctx, failed_list, 10_000)
          handle_release(socket)
        end)

      assert {:ok, %Result{status: 0xA702, completed: 1, failed: 2, warning: 1}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      wait_for_server(pid)
    end

    test "keeps the last counts when the final response omits them", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)
          send_command(socket, get_ctx, cget_rsp(0xFF00, remaining: 0, completed: 4, warning: 1))
          send_command(socket, get_ctx, cget_rsp(0x0000))
          handle_release(socket)
        end)

      assert {:ok, %Result{status: 0x0000, completed: 4, warning: 1, failed: 0}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      wait_for_server(pid)
    end
  end

  describe "get/3 - query model" do
    test "uses the Study Root GET SOP class for :study_root", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          {get_ctx, get_rq} = recv_command(socket)
          _ = recv_dataset(socket)
          send_parent({:get_rq, get_rq})
          send_command(socket, get_ctx, cget_rsp(0x0000, completed: 0))
          handle_release(socket)
        end)

      assert {:ok, %Result{status: 0}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 query_model: :study_root,
                 storage_sop_classes: [@ct_storage]
               )

      assert_received {:associate_rq, proposed}
      assert hd(proposed.contexts).abstract_syntax == @study_root_get
      assert_received {:get_rq, %{affected_sop_class_uid: @study_root_get}}
      wait_for_server(pid)
    end

    test "proposes dcmtk's storage classes by default", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)
          send_command(socket, get_ctx, cget_rsp(0x0000))
          handle_release(socket)
        end)

      assert {:ok, %Result{}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"), output_directory: dir)

      assert_received {:associate_rq, proposed}
      assert length(proposed.contexts) == 121
      assert length(proposed.roles) == 120
      wait_for_server(pid)
    end
  end

  describe "get/3 - failures" do
    test "returns association_aborted and removes the partial file", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          {_get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)

          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.11", 2))
          :ok = :gen_tcp.send(socket, pdata([{ctx[@ct_storage], 0x00, "partial"}]))
          :ok = :gen_tcp.send(socket, PDU.encode_abort(2, 0))
        end)

      assert {:error, :association_aborted} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert File.ls!(dir) == []
      wait_for_server(pid)
    end

    test "sends C-CANCEL-RQ on timeout and returns the cancel response", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)

          send_parent({:cancel, recv_command(socket)})
          send_command(socket, get_ctx, cget_rsp(0xFE00, completed: 0, failed: 0))
          handle_release(socket)
        end)

      assert {:error, {:timeout, %Result{status: 0xFE00}}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage],
                 timeout: 300
               )

      assert_received {:cancel, {1, cancel}}
      assert cancel.command_field == 0x0FFF
      assert cancel.message_id_being_responded_to == 1
      wait_for_server(pid)
    end

    test "aborts when the cancel goes unanswered", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          _ = recv_command(socket)
          _ = recv_dataset(socket)
          _ = recv_command(socket)
          send_parent({:closed, :gen_tcp.recv(socket, 0, 5_000)})
        end)

      assert {:error, {:timeout, %Result{status: nil}}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage],
                 timeout: 200
               )

      # Client sent A-ABORT rather than A-RELEASE-RQ
      assert_receive {:closed, {:ok, <<0x07, _::binary>>}}, 5_000
      wait_for_server(pid)
    end

    test "a stall partway through a PDU aborts and keeps completed files", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          _ = recv_command(socket)
          _ = recv_dataset(socket)

          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.30", 2))
          send_data(socket, ctx[@ct_storage], ct_dataset("1.2.3.30"), 10_000)
          _ = recv_command(socket)

          # Second instance: its data PDU stalls after the header
          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.31", 3))
          :ok = :gen_tcp.send(socket, <<0x04, 0x00, 100::32-big, 0, 0, 0, 10>>)
          send_parent({:after_stall, :gen_tcp.recv(socket, 0, 5_000)})
        end)

      assert {:error, {:timeout, %Result{files: [path]}}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage],
                 timeout: 200
               )

      assert path == Path.join(dir, "1.2.3.30")
      assert File.ls!(dir) == ["1.2.3.30"]

      # A-ABORT, not a C-CANCEL P-DATA
      assert_receive {:after_stall, {:ok, <<0x07, _::binary>>}}, 5_000
      wait_for_server(pid)
    end

    test "a stall partway through a PDU after the cancel still returns the Result", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          _ = recv_command(socket)
          _ = recv_dataset(socket)

          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.32", 2))
          send_data(socket, ctx[@ct_storage], ct_dataset("1.2.3.32"), 10_000)
          _ = recv_command(socket)

          # Go quiet until the cancel, then stall mid-PDU
          {_ctx, %{command_field: 0x0FFF}} = recv_command(socket)
          :ok = :gen_tcp.send(socket, <<0x04, 0x00, 100::32-big, 0, 0>>)
          send_parent({:after_stall, :gen_tcp.recv(socket, 0, 5_000)})
        end)

      assert {:error, {:timeout, %Result{status: nil, files: [_]}}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage],
                 timeout: 200
               )

      assert_receive {:after_stall, {:ok, <<0x07, _::binary>>}}, 5_000
      wait_for_server(pid)
    end

    test "the cancel deadline holds while the SCP keeps sending sub-operations", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          _ = recv_command(socket)
          _ = recv_dataset(socket)
          {_ctx, %{command_field: 0x0FFF}} = recv_command(socket)
          send_parent(:cancelled)
          keep_storing(socket, ctx[@ct_storage], 1)
        end)

      started = System.monotonic_time(:millisecond)

      assert {:error, {:timeout, %Result{status: nil, files: files}}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage],
                 timeout: 300
               )

      elapsed = System.monotonic_time(:millisecond) - started
      assert_received :cancelled
      # 300 ms to the cancel, then the 300 ms deadline, not one per read
      assert elapsed < 2_000
      # Sub-operations arriving before the deadline are still stored
      assert files != []
      assert_receive {:stores_sent, sent}, 5_000
      assert length(files) <= sent
      wait_for_server(pid)
    end

    test "aborts on a P-DATA PDU larger than the proposed maximum", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          _ = recv_command(socket)
          _ = recv_dataset(socket)
          :ok = :gen_tcp.send(socket, <<0x04, 0x00, 1_025::32-big>>)
          send_parent({:after_oversize, :gen_tcp.recv(socket, 0, 5_000)})
        end)

      assert {:error, :pdu_too_large} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage],
                 max_pdu_length: 1_024
               )

      assert_receive {:after_oversize, {:ok, <<0x07, _::binary>>}}, 5_000
      wait_for_server(pid)
    end

    test "returns unexpected_release when the SCP releases mid-operation", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          _ = recv_command(socket)
          _ = recv_dataset(socket)
          :ok = :gen_tcp.send(socket, PDU.encode_release_rq())
        end)

      assert {:error, :unexpected_release} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      wait_for_server(pid)
    end

    test "returns an error for an unexpected DIMSE command", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)
          send_command(socket, get_ctx, command([{0x0100, 0x8020}, {0x0900, 0}]))
        end)

      assert {:error, {:unexpected_command, 0x8020}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      wait_for_server(pid)
    end

    test "returns an error for a data fragment with no command", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)
          :ok = :gen_tcp.send(socket, pdata([{get_ctx, 0x02, "stray"}]))
        end)

      assert {:error, :unexpected_data_fragment} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      wait_for_server(pid)
    end

    test "returns an error for a command interrupting a data set", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)
          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.12", 2))
          :ok = :gen_tcp.send(socket, pdata([{ctx[@ct_storage], 0x00, "part"}]))
          send_command(socket, get_ctx, cget_rsp(0x0000))
        end)

      assert {:error, :unexpected_command_fragment} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert File.ls!(dir) == []
      wait_for_server(pid)
    end

    test "returns an error for data on a different context", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)
          send_command(socket, ctx[@ct_storage], cstore_rq(@ct_storage, "1.2.3.13", 2))
          :ok = :gen_tcp.send(socket, pdata([{get_ctx, 0x02, "data"}]))
        end)

      assert {:error, {:unexpected_data_context, 1}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      wait_for_server(pid)
    end

    test "returns an error for an undecodable command", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          {get_ctx, _} = recv_command(socket)
          _ = recv_dataset(socket)
          :ok = :gen_tcp.send(socket, pdata([{get_ctx, 0x03, <<0, 0, 0, 0, 9, 0, 0, 0>>}]))
        end)

      assert {:error, :invalid_command} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      wait_for_server(pid)
    end

    test "returns an error when the connection drops", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          _ = recv_command(socket)
          _ = recv_dataset(socket)
        end)

      assert {:error, {:recv_failed, :closed}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      wait_for_server(pid)
    end

    test "returns an error for an unexpected PDU type", %{dir: dir} do
      {port, pid} =
        start_scp(fn socket, _ctx ->
          _ = recv_command(socket)
          _ = recv_dataset(socket)
          :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)
        end)

      assert {:error, {:unexpected_pdu, :release_rp}} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      wait_for_server(pid)
    end

    test "releases and errors when the GET context is not accepted", %{dir: dir} do
      {port, pid} =
        start_scp(
          fn socket, _ctx ->
            send_parent({:release, recv_raw_pdu(socket)})
            :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)
          end,
          accept: %{@ct_storage => @implicit_vr_le}
        )

      assert {:error, :no_accepted_presentation_context} =
               CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage]
               )

      assert_receive {:release, {:ok, <<0x05, _::binary>>}}, 5_000
      wait_for_server(pid)
    end

    test "returns an error for connection failure", %{dir: dir} do
      assert {:error, {:connection_failed, _}} =
               CGet.get("127.0.0.1:1", study_identifier("1.2.3"), output_directory: dir)
    end

    test "validates options before connecting" do
      query = study_identifier("1.2.3")

      assert {:error, {:invalid_query_model, :bogus}} =
               CGet.get("127.0.0.1:1", query, query_model: :bogus)

      assert {:error, {:invalid_storage_mode, :memory}} =
               CGet.get("127.0.0.1:1", query, storage_mode: :memory)

      too_many = Enum.map(1..128, &"1.2.3.#{&1}")

      assert {:error, {:too_many_presentation_contexts, 129}} =
               CGet.get("127.0.0.1:1", query, storage_sop_classes: too_many)
    end
  end

  describe "get/3 - logging" do
    test "warns when no storage context was granted the SCP role", %{dir: dir} do
      {port, pid} = start_scp(single_store_script(@ct_storage, "1.2.3.25"), scp_role: false)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %Result{}} =
                   CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                     output_directory: dir,
                     storage_sop_classes: [@ct_storage]
                   )
        end)

      assert log =~ "SCP role"
      wait_for_server(pid)
    end

    test "does not warn when the SCP role was granted", %{dir: dir} do
      {port, pid} = start_scp(single_store_script(@ct_storage, "1.2.3.26"))

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %Result{}} =
                   CGet.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                     output_directory: dir,
                     storage_sop_classes: [@ct_storage]
                   )
        end)

      refute log =~ "SCP role"
      wait_for_server(pid)
    end

    @tag capture_log: true
    test "runs with verbose logging enabled", %{dir: dir} do
      {port, pid} = start_scp(single_store_script(@ct_storage, "1.2.3.14"))

      assert {:ok, %Result{files: [_]}} =
               Dcmix.Network.get("127.0.0.1:#{port}", study_identifier("1.2.3"),
                 output_directory: dir,
                 storage_sop_classes: [@ct_storage],
                 verbose: true
               )

      wait_for_server(pid)
    end
  end

  # ===========================================================================
  # Fixtures
  # ===========================================================================

  defp study_identifier(study_uid) do
    DataSet.new()
    |> DataSet.put_element({0x0008, 0x0052}, :CS, "STUDY")
    |> DataSet.put_element({0x0020, 0x000D}, :UI, study_uid)
  end

  defp ct_dataset(sop_instance_uid, patient_id \\ "PID-1") do
    DataSet.new()
    |> DataSet.put_element({0x0008, 0x0016}, :UI, @ct_storage)
    |> DataSet.put_element({0x0008, 0x0018}, :UI, sop_instance_uid)
    |> DataSet.put_element({0x0010, 0x0020}, :LO, patient_id)
    |> Writer.ImplicitVR.encode()
  end

  # Splits a Part 10 file into its transfer syntax and raw data set bytes
  defp split_part10(bytes) do
    {group_length, rest} = file_meta_group(bytes)
    <<meta::binary-size(group_length), dataset::binary>> = rest
    {:ok, meta_ds, _} = Parser.ExplicitVR.parse(meta)
    {DataSet.get_string(meta_ds, {0x0002, 0x0010}), dataset}
  end

  defp stored_dataset(path) do
    {_ts, dataset} = split_part10(File.read!(path))
    dataset
  end

  defp file_meta_group(
         <<_preamble::binary-size(128), "DICM", 0x0002::16-little, 0x0000::16-little, "UL",
           4::16-little, group_length::32-little, rest::binary>>
       ),
       do: {group_length, rest}

  # Sends a C-STORE every 50 ms until the client stops answering. Sends are
  # unchecked because the client may abort at any point.
  defp keep_storing(socket, context_id, n) do
    uid = "1.2.3.40.#{n}"

    _ =
      :gen_tcp.send(
        socket,
        pdata([
          {context_id, 0x03, cstore_rq(@ct_storage, uid, n + 1)},
          {context_id, 0x02, ct_dataset(uid)}
        ])
      )

    case recv_raw_pdu(socket) do
      {:ok, <<0x04, _::binary>>} ->
        Process.sleep(50)
        keep_storing(socket, context_id, n + 1)

      _ ->
        send_parent({:stores_sent, n})
    end
  end

  defp single_store_script(sop_class, sop_instance_uid) do
    fn socket, ctx ->
      {get_ctx, _} = recv_command(socket)
      _ = recv_dataset(socket)
      send_command(socket, ctx[sop_class], cstore_rq(sop_class, sop_instance_uid, 5))
      send_data(socket, ctx[sop_class], ct_dataset(sop_instance_uid), 10_000)
      send_parent({:store_rsp, recv_command(socket)})
      send_command(socket, get_ctx, cget_rsp(0x0000, completed: 1))
      handle_release(socket)
    end
  end

  # ===========================================================================
  # Mock C-GET SCP
  # ===========================================================================

  defp start_scp(script, opts \\ []) do
    accept = Keyword.get(opts, :accept, @default_accept)
    grant_scp_role = Keyword.get(opts, :scp_role, true)
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        Process.put(:parent, parent)

        try do
          {:ok, socket} = :gen_tcp.accept(listen, 5_000)
          {:ok, rq} = recv_raw_pdu(socket)
          proposed = parse_associate_rq(rq)
          send(parent, {:associate_rq, proposed})

          accepted =
            for pc <- proposed.contexts, Map.has_key?(accept, pc.abstract_syntax) do
              {pc.id, accept[pc.abstract_syntax]}
            end

          scp_roles =
            for {uid, _scu, 1} <- proposed.roles,
                grant_scp_role,
                Map.has_key?(accept, uid),
                do: uid

          :ok = :gen_tcp.send(socket, build_associate_ac(proposed.contexts, accepted, scp_roles))

          ctx =
            Map.new(proposed.contexts, &{&1.abstract_syntax, &1.id})
            |> Map.filter(fn {uid, _} -> Map.has_key?(accept, uid) end)

          script.(socket, ctx)
          :gen_tcp.close(socket)
        after
          :gen_tcp.close(listen)
          send(parent, {:server_done, self()})
        end
      end)

    {port, pid}
  end

  defp send_parent(message), do: send(Process.get(:parent), message)

  defp wait_for_server(pid) do
    receive do
      {:server_done, ^pid} -> :ok
    after
      5_000 -> :ok
    end
  end

  defp recv_raw_pdu(socket) do
    with {:ok, <<_type, _reserved, length::32-big>> = header} <- :gen_tcp.recv(socket, 6, 5_000),
         {:ok, payload} <- recv_payload(socket, length) do
      {:ok, header <> payload}
    end
  end

  defp recv_payload(_socket, 0), do: {:ok, <<>>}
  defp recv_payload(socket, length), do: :gen_tcp.recv(socket, length, 5_000)

  defp recv_pdvs(socket) do
    {:ok, raw} = recv_raw_pdu(socket)
    {:ok, {:p_data, pdvs}, _} = PDU.decode_pdu(raw)
    pdvs
  end

  # Reads PDVs until the last fragment of the given kind
  defp recv_fragments(socket, is_command, acc \\ <<>>) do
    pdvs = recv_pdvs(socket)
    data = for %{is_command: ^is_command, data: d} <- pdvs, into: acc, do: d
    last = Enum.find(pdvs, &(&1.is_command == is_command and &1.is_last))

    if last, do: {last.context_id, data}, else: recv_fragments(socket, is_command, data)
  end

  defp recv_command(socket) do
    {context_id, bytes} = recv_fragments(socket, true)
    {:ok, command} = DIMSE.decode_command(bytes)
    {context_id, command}
  end

  defp recv_dataset(socket) do
    {_context_id, bytes} = recv_fragments(socket, false)
    bytes
  end

  defp send_command(socket, context_id, command) do
    :ok = :gen_tcp.send(socket, pdata([{context_id, 0x03, command}]))
  end

  defp send_data(socket, context_id, data, chunk_size) when byte_size(data) > chunk_size do
    <<chunk::binary-size(chunk_size), rest::binary>> = data
    :ok = :gen_tcp.send(socket, pdata([{context_id, 0x00, chunk}]))
    send_data(socket, context_id, rest, chunk_size)
  end

  defp send_data(socket, context_id, data, _chunk_size) do
    :ok = :gen_tcp.send(socket, pdata([{context_id, 0x02, data}]))
  end

  defp handle_release(socket) do
    case recv_raw_pdu(socket) do
      {:ok, <<0x05, _::binary>>} -> :ok = :gen_tcp.send(socket, <<0x06, 0x00, 4::32-big, 0::32>>)
      _ -> :ok
    end
  end

  defp pdata(pdvs) do
    items =
      for {context_id, control, data} <- pdvs, into: <<>> do
        <<byte_size(data) + 2::32-big, context_id, control, data::binary>>
      end

    <<0x04, 0x00, byte_size(items)::32-big, items::binary>>
  end

  # ===========================================================================
  # Command sets (Implicit VR Little Endian)
  # ===========================================================================

  defp cget_rsp(status, counts \\ [], with_dataset \\ false) do
    count_tags = %{remaining: 0x1020, completed: 0x1021, failed: 0x1022, warning: 0x1023}

    command(
      [
        {0x0002, @patient_root_get},
        {0x0100, 0x8010},
        {0x0120, 1},
        {0x0800, if(with_dataset, do: 0x0000, else: 0x0101)},
        {0x0900, status}
      ] ++ Enum.map(counts, fn {key, value} -> {count_tags[key], value} end)
    )
  end

  defp cstore_rq(sop_class, sop_instance_uid, message_id) do
    command([
      {0x0002, sop_class},
      {0x0100, 0x0001},
      {0x0110, message_id},
      {0x0700, 0},
      {0x0800, 0x0000},
      {0x1000, sop_instance_uid}
    ])
  end

  defp command(elements) do
    body =
      for {element, value} <- Enum.sort(elements), into: <<>> do
        bytes = command_value(value)
        <<0x0000::16-little, element::16-little, byte_size(bytes)::32-little, bytes::binary>>
      end

    <<0x0000::16-little, 0x0000::16-little, 4::32-little, byte_size(body)::32-little,
      body::binary>>
  end

  defp command_value(value) when is_integer(value), do: <<value::16-little>>
  defp command_value(value) when rem(byte_size(value), 2) == 1, do: value <> <<0>>
  defp command_value(value), do: value

  # ===========================================================================
  # A-ASSOCIATE-RQ parsing / A-ASSOCIATE-AC building
  # ===========================================================================

  defp parse_associate_rq(<<0x01, _, _len::32, _header::binary-size(68), items::binary>>) do
    parse_rq_items(items, %{contexts: [], roles: []})
  end

  defp parse_rq_items(<<>>, acc),
    do: %{contexts: Enum.reverse(acc.contexts), roles: Enum.reverse(acc.roles)}

  defp parse_rq_items(<<0x20, _, len::16-big, item::binary-size(len), rest::binary>>, acc) do
    <<id, _::24, sub_items::binary>> = item
    [abstract_syntax | transfer_syntaxes] = sub_item_values(sub_items)

    pc = %{id: id, abstract_syntax: abstract_syntax, transfer_syntaxes: transfer_syntaxes}
    parse_rq_items(rest, %{acc | contexts: [pc | acc.contexts]})
  end

  defp parse_rq_items(<<0x50, _, len::16-big, item::binary-size(len), rest::binary>>, acc) do
    parse_rq_items(rest, %{acc | roles: parse_roles(item, acc.roles)})
  end

  defp parse_rq_items(<<_type, _, len::16-big, _::binary-size(len), rest::binary>>, acc),
    do: parse_rq_items(rest, acc)

  defp parse_roles(<<>>, roles), do: roles

  defp parse_roles(
         <<0x54, _, len::16-big, uid_len::16-big, uid::binary-size(uid_len), scu, scp,
           rest::binary>>,
         roles
       )
       when len == uid_len + 4,
       do: parse_roles(rest, [{uid, scu, scp} | roles])

  defp parse_roles(<<_type, _, len::16-big, _::binary-size(len), rest::binary>>, roles),
    do: parse_roles(rest, roles)

  defp sub_item_values(<<>>), do: []

  defp sub_item_values(<<_type, _, len::16-big, value::binary-size(len), rest::binary>>),
    do: [value | sub_item_values(rest)]

  defp build_associate_ac(contexts, accepted, scp_roles) do
    accepted = Map.new(accepted)

    pc_items =
      for %{id: id} <- contexts, into: <<>> do
        {result, ts} =
          case Map.fetch(accepted, id) do
            {:ok, ts} -> {0, ts}
            :error -> {3, @implicit_vr_le}
          end

        ts_item = <<0x40, 0x00, byte_size(ts)::16-big, ts::binary>>
        content = <<id, 0x00, result, 0x00, ts_item::binary>>
        <<0x21, 0x00, byte_size(content)::16-big, content::binary>>
      end

    role_items =
      for uid <- scp_roles, into: <<>> do
        <<0x54, 0x00, byte_size(uid) + 4::16-big, byte_size(uid)::16-big, uid::binary, 0, 1>>
      end

    user_info_content = <<0x51, 0x00, 4::16-big, 16_384::32-big, role_items::binary>>

    user_info =
      <<0x50, 0x00, byte_size(user_info_content)::16-big, user_info_content::binary>>

    payload =
      IO.iodata_to_binary([
        <<1::16-big, 0::16>>,
        String.pad_trailing("TEST_SCP", 16),
        String.pad_trailing("TEST_SCU", 16),
        <<0::256>>,
        <<0x10, 0x00, 21::16-big, "1.2.840.10008.3.1.1.1">>,
        pc_items,
        user_info
      ])

    <<0x02, 0x00, byte_size(payload)::32-big, payload::binary>>
  end
end
