defmodule Dcmix.Network.StorageSCPTest do
  use ExUnit.Case, async: true

  alias Dcmix.{DataSet, Network, Tag}
  alias Dcmix.Network.{Association, DIMSE, Listener, PDU, SOPClassUID}
  alias Dcmix.Parser.TransferSyntax
  alias Dcmix.Writer.{ExplicitVR, ImplicitVR}

  require Dcmix.Network.DIMSE.CommandField, as: CommandField
  require Dcmix.Network.DIMSE.Status, as: Status
  require Dcmix.Network.PDU.PresentationContextResult, as: ContextResult

  @moduletag capture_log: true

  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"
  @mr_image_storage "1.2.840.10008.5.1.4.1.1.4"

  defmodule Handler do
    @moduledoc false
    @behaviour Dcmix.Network.SCP.Handler

    @impl true
    def init(association, %{test: test} = arg) do
      send(test, {:init, association})
      {:ok, Map.put(arg, :count, 0)}
    end

    @impl true
    def handle_store(instance, state) do
      state = %{state | count: state.count + 1}
      send(state.test, {:stored, instance, state.count})

      case Map.get(state, :reply) do
        :raise -> raise "handler failed"
        nil -> {:reply, 0x0000, state}
        status -> {:reply, status, state}
      end
    end
  end

  defmodule StatelessHandler do
    @moduledoc false
    @behaviour Dcmix.Network.SCP.Handler

    @impl true
    def handle_store(_instance, nil), do: {:reply, 0x0000, nil}
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "dcmix_storage_scp_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp start_listener(dir, opts \\ []) do
    handler_arg = Map.merge(%{test: self()}, Map.new(Keyword.get(opts, :handler_arg, [])))

    defaults = [
      port: 0,
      ae_title: "SCP",
      handler: {Handler, handler_arg},
      storage_directory: dir
    ]

    listener =
      start_supervised!({Listener, Keyword.merge(defaults, Keyword.delete(opts, :handler_arg))})

    {:ok, port} = Listener.port(listener)
    "localhost:#{port}"
  end

  defp open(addr, contexts) do
    Association.request(addr,
      called_ae_title: "SCP",
      presentation_contexts: contexts,
      timeout: 5_000
    )
  end

  defp ct_context(transfer_syntaxes \\ [TransferSyntax.implicit_vr_little_endian()]),
    do: %{abstract_syntax: @ct_image_storage, transfer_syntaxes: transfer_syntaxes}

  defp open_ct(addr) do
    {:ok, assoc} = open(addr, [ct_context()])
    {:ok, pc} = Association.accepted_context(assoc, @ct_image_storage)
    {assoc, pc}
  end

  defp data_set(patient_id, transfer_syntax) do
    ds = DataSet.put_element(DataSet.new(), {0x0010, 0x0020}, :LO, patient_id)

    if transfer_syntax == TransferSyntax.implicit_vr_little_endian(),
      do: ImplicitVR.encode(ds),
      else: ExplicitVR.encode(ds, big_endian: false)
  end

  defp store(assoc, pc, uid, opts \\ []) do
    message_id = Keyword.get(opts, :message_id, 1)
    command = DIMSE.build_cstore_rq(@ct_image_storage, uid, message_id, opts)
    data = Keyword.get_lazy(opts, :data, fn -> data_set("PID-1", pc.transfer_syntax) end)

    :ok = Association.send_pdata(assoc, pc.id, true, command)
    :ok = Association.send_pdata(assoc, pc.id, false, data)
    receive_rsp(assoc)
  end

  defp receive_rsp(assoc) do
    {:ok, {:p_data, [pdv]}} = Association.receive_pdu(assoc, 5_000)
    {:ok, rsp} = DIMSE.decode_command(pdv.data)
    assert rsp.command_field == CommandField.c_store_rsp()
    rsp
  end

  describe "C-STORE" do
    test "stores the instance and hands it to the handler", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir))

      rsp = store(assoc, pc, "1.2.3.4", message_id: 7)

      assert rsp.status == Status.success()
      assert rsp.message_id_being_responded_to == 7
      assert rsp.affected_sop_instance_uid == "1.2.3.4"

      assert_received {:stored, instance, 1}

      assert instance == %{
               path: Path.join(dir, "1.2.3.4"),
               sop_class_uid: @ct_image_storage,
               sop_instance_uid: "1.2.3.4",
               transfer_syntax: TransferSyntax.implicit_vr_little_endian(),
               calling_ae_title: "DCMIX",
               move_originator_ae_title: nil,
               move_originator_message_id: nil
             }

      {:ok, ds} = Dcmix.read_file(instance.path)
      assert DataSet.get_string(ds, {0x0010, 0x0020}) == "PID-1"
      assert DataSet.get_value(ds, Tag.media_storage_sop_instance_uid()) == "1.2.3.4"
      assert DataSet.get_string(ds, {0x0002, 0x0016}) == "DCMIX"

      Association.release(assoc)
    end

    test "starts the handler once per association and keeps its state", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir))

      store(assoc, pc, "1.2.3.4")
      store(assoc, pc, "1.2.3.5", message_id: 2)

      assert_received {:init, %{calling_ae_title: "DCMIX", called_ae_title: "SCP", peer: {_, _}}}
      refute_received {:init, _}
      assert_received {:stored, %{sop_instance_uid: "1.2.3.4"}, 1}
      assert_received {:stored, %{sop_instance_uid: "1.2.3.5"}, 2}

      Association.release(assoc)
    end

    test "answers with the handler's status", %{dir: dir} do
      warning = 0xB000
      {assoc, pc} = open_ct(start_listener(dir, handler_arg: [reply: warning]))

      assert store(assoc, pc, "1.2.3.4").status == warning
      Association.release(assoc)
    end

    test "passes on the Move Originator of a C-MOVE sub-operation", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir))

      store(assoc, pc, "1.2.3.4",
        move_originator_ae_title: "MOVER",
        move_originator_message_id: 42
      )

      assert_received {:stored,
                       %{move_originator_ae_title: "MOVER", move_originator_message_id: 42}, 1}

      Association.release(assoc)
    end

    test "reads a data set split across PDUs", %{dir: dir} do
      # The listener's 1 KiB max PDU length makes the requestor split the data set
      {assoc, pc} = open_ct(start_listener(dir, max_pdu_length: 1_024))
      comments = String.duplicate("a", 3_000)

      data =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "PID-1")
        |> DataSet.put_element({0x0010, 0x4000}, :LT, comments)
        |> ImplicitVR.encode()

      assert store(assoc, pc, "1.2.3.4", data: data).status == Status.success()

      assert_received {:stored, %{path: path}, 1}
      {:ok, ds} = Dcmix.read_file(path)
      assert DataSet.get_string(ds, {0x0010, 0x4000}) == comments

      Association.release(assoc)
    end

    test "takes a compressed transfer syntax as sent", %{dir: dir} do
      jpeg = TransferSyntax.jpeg_baseline()
      {:ok, assoc} = open(start_listener(dir), [ct_context([jpeg])])
      {:ok, pc} = Association.accepted_context(assoc, @ct_image_storage)

      assert pc.transfer_syntax == jpeg
      assert store(assoc, pc, "1.2.3.4").status == Status.success()

      assert_received {:stored, %{path: path, transfer_syntax: ^jpeg}, 1}
      {:ok, ds} = Dcmix.read_file(path, stop_before_pixels: true)
      assert DataSet.get_value(ds, Tag.transfer_syntax_uid()) == jpeg

      Association.release(assoc)
    end

    test "accepts the requestor's most preferred transfer syntax", %{dir: dir} do
      proposed = [TransferSyntax.jpeg_2000_lossless(), TransferSyntax.explicit_vr_little_endian()]
      {:ok, assoc} = open(start_listener(dir), [ct_context(proposed)])

      assert {:ok, %{transfer_syntax: transfer_syntax}} =
               Association.accepted_context(assoc, @ct_image_storage)

      assert transfer_syntax == TransferSyntax.jpeg_2000_lossless()
      Association.release(assoc)
    end

    test "works with a handler that has no init/2", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir, handler: StatelessHandler))

      assert store(assoc, pc, "1.2.3.4").status == Status.success()
      assert File.exists?(Path.join(dir, "1.2.3.4"))
      Association.release(assoc)
    end
  end

  describe "instances dcmix can't store" do
    test "a C-STORE-RQ without a data set is Cannot Understand", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir))
      command = DIMSE.build_cstore_rq(@ct_image_storage, "1.2.3.4", 1)

      :ok = Association.send_pdata(assoc, pc.id, true, without_data_set(command))

      assert receive_rsp(assoc).status == Status.cannot_understand()
      refute_received {:stored, _, _}
      Association.release(assoc)
    end

    test "a UID that can't name a file is Cannot Understand, and the association goes on",
         %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir))

      assert store(assoc, pc, "..").status == Status.cannot_understand()
      refute_received {:stored, _, _}
      assert File.ls!(dir) == []

      assert store(assoc, pc, "1.2.3.4", message_id: 2).status == Status.success()
      Association.release(assoc)
    end

    test "a storage directory that can't be written is Out of Resources", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir))
      File.rm_rf!(dir)

      assert store(assoc, pc, "1.2.3.4").status == Status.out_of_resources()
      refute_received {:stored, _, _}
      Association.release(assoc)
    end
  end

  describe "a handler that raises" do
    test "closes the connection without a C-STORE-RSP", %{dir: dir} do
      addr = start_listener(dir, handler_arg: [reply: :raise])
      {assoc, pc} = open_ct(addr)
      command = DIMSE.build_cstore_rq(@ct_image_storage, "1.2.3.4", 1)

      :ok = Association.send_pdata(assoc, pc.id, true, command)
      :ok = Association.send_pdata(assoc, pc.id, false, data_set("PID-1", pc.transfer_syntax))

      assert {:error, {:recv_failed, :closed}} = Association.receive_pdu(assoc, 5_000)
      assert Network.echo(addr, called_ae_title: "SCP") == :ok
    end
  end

  describe "an instance cut short" do
    test "by an abort deletes its .part file", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir))
      start_instance(assoc, pc, dir)

      Association.abort(assoc)
      assert eventually(fn -> File.ls!(dir) == [] end)
      refute_received {:stored, _, _}
    end

    test "by the timeout deletes its .part file and aborts", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir, timeout: 100))
      start_instance(assoc, pc, dir)

      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
      assert eventually(fn -> File.ls!(dir) == [] end)
    end

    test "by a command deletes its .part file and aborts", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir))
      start_instance(assoc, pc, dir)

      :ok = Association.send_pdata(assoc, pc.id, true, DIMSE.build_cecho_rq(2))
      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
      assert eventually(fn -> File.ls!(dir) == [] end)
    end

    test "by a release request deletes its .part file and aborts", %{dir: dir} do
      {assoc, pc} = open_ct(start_listener(dir))
      start_instance(assoc, pc, dir)

      :ok = :gen_tcp.send(assoc.socket, PDU.encode_release_rq())
      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
      assert eventually(fn -> File.ls!(dir) == [] end)
    end
  end

  describe "negotiation" do
    test "rejects storage contexts on a listener without a handler", %{dir: dir} do
      listener = start_supervised!({Listener, port: 0, ae_title: "SCP"})
      {:ok, port} = Listener.port(listener)
      {:ok, assoc} = open("localhost:#{port}", [ct_context()])

      assert [%{result: ContextResult.abstract_syntax_not_supported()}] =
               assoc.presentation_contexts

      Association.release(assoc)
      refute File.exists?(dir)
    end

    test "accepts only the Storage SOP Classes given", %{dir: dir} do
      addr = start_listener(dir, storage_sop_classes: [@mr_image_storage])
      mr = %{ct_context() | abstract_syntax: @mr_image_storage}
      {:ok, assoc} = open(addr, [ct_context(), mr])

      assert Enum.map(assoc.presentation_contexts, & &1.result) == [
               ContextResult.abstract_syntax_not_supported(),
               ContextResult.acceptance()
             ]

      Association.release(assoc)
    end

    test "accepts only the transfer syntaxes given", %{dir: dir} do
      addr =
        start_listener(dir,
          storage_transfer_syntaxes: [TransferSyntax.explicit_vr_little_endian()]
        )

      {:ok, assoc} = open(addr, [ct_context()])

      assert [%{result: ContextResult.transfer_syntaxes_not_supported()}] =
               assoc.presentation_contexts

      Association.release(assoc)
    end

    test "aborts a C-STORE-RQ on the Verification context", %{dir: dir} do
      verification = %{
        abstract_syntax: SOPClassUID.verification(),
        transfer_syntaxes: [TransferSyntax.implicit_vr_little_endian()]
      }

      {:ok, assoc} = open(start_listener(dir), [verification])
      {:ok, pc} = Association.accepted_context(assoc)

      :ok =
        Association.send_pdata(
          assoc,
          pc.id,
          true,
          DIMSE.build_cstore_rq(@ct_image_storage, "1.2.3.4", 1)
        )

      assert {:ok, {:abort, _}} = Association.receive_pdu(assoc, 5_000)
    end
  end

  describe "start_link/1" do
    test "creates the storage directory", %{dir: dir} do
      start_listener(Path.join(dir, "nested"))
      assert File.dir?(Path.join(dir, "nested"))
    end

    test "requires a storage directory with a handler" do
      assert_raise KeyError, fn ->
        Listener.start_link(port: 0, ae_title: "SCP", handler: StatelessHandler)
      end
    end

    test "returns an error when the storage directory can't be created", %{dir: dir} do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "file"), "")

      assert {:error, {:storage_directory, _reason}} =
               Listener.start_link(
                 port: 0,
                 ae_title: "SCP",
                 handler: StatelessHandler,
                 storage_directory: Path.join([dir, "file", "under"])
               )
    end
  end

  # Sends a C-STORE-RQ and the first fragment of its data set, so the
  # instance is left part-written
  defp start_instance(assoc, pc, dir) do
    command = DIMSE.build_cstore_rq(@ct_image_storage, "1.2.3.4", 1)
    :ok = Association.send_pdata(assoc, pc.id, true, command)
    :ok = :gen_tcp.send(assoc.socket, PDU.encode_p_data(pc.id, false, false, <<0x10, 0x00>>))
    assert eventually(fn -> File.ls!(dir) == ["1.2.3.4.part"] end)
  end

  # Command Data Set Type (0000,0800) changed to 0x0101, no data set
  defp without_data_set(command) do
    :binary.replace(
      command,
      <<0x00, 0x00, 0x00, 0x08, 2::32-little, 0x0001::16-little>>,
      <<0x00, 0x00, 0x00, 0x08, 2::32-little, 0x0101::16-little>>
    )
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(fun, attempts - 1)
    end
  end
end
