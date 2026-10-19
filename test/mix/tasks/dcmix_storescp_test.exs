defmodule Mix.Tasks.Dcmix.StorescpTest do
  # Mix.shell/1 is global
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Dcmix.DataSet
  alias Dcmix.Network
  alias Dcmix.Network.{Association, DIMSE, Listener}
  alias Dcmix.Parser.TransferSyntax
  alias Dcmix.Writer.ImplicitVR
  alias Mix.Tasks.Dcmix.Storescp

  require Dcmix.Network.DIMSE.Status, as: Status

  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    dir = Path.join(System.tmp_dir!(), "dcmix_storescp_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp start!(args) do
    # Linked to the test process, so it stops when the test does
    assert {:ok, listener} = Storescp.start(args)
    {:ok, port} = Listener.port(listener)
    "localhost:#{port}"
  end

  describe "start/1" do
    test "answers C-ECHO and stores instances, logging each one", %{dir: dir} do
      addr = start!(["-aet", "SCP", "-od", dir, "-td", "30", "0"])

      assert_received {:mix_shell, :info, ["Storage SCP SCP listening on port " <> listening]}
      assert listening =~ "storing to #{dir}"

      assert Network.echo(addr, called_ae_title: "SCP") == :ok

      log = capture_log(fn -> assert store(addr, "1.2.3.4") == Status.success() end)

      assert log =~ "Stored #{Path.join(dir, "1.2.3.4")}"
      assert log =~ "SOP Class #{@ct_image_storage}"
      assert log =~ "from DCMIX"
      assert {:ok, ds} = Dcmix.read_file(Path.join(dir, "1.2.3.4"))
      assert DataSet.get_string(ds, {0x0010, 0x0020}) == "PID-1"
    end

    test "logs the Move Originator of a C-MOVE sub-operation", %{dir: dir} do
      addr = start!(["-aet", "SCP", "-od", dir, "0"])

      log =
        capture_log(fn ->
          store(addr, "1.2.3.4", move_originator_ae_title: "MOVER", move_originator_message_id: 7)
        end)

      assert log =~ "moved for MOVER (message 7)"
    end

    test "uses DCMIX as the AE title by default", %{dir: dir} do
      addr = start!(["-od", dir, "0"])
      assert Network.echo(addr, called_ae_title: "DCMIX") == :ok
    end

    test "rejects associations beyond --max-associations", %{dir: dir} do
      addr = start!(["-aet", "SCP", "-od", dir, "--max-associations", "1", "0"])
      {:ok, held} = open(addr)

      assert {:error, {:association_rejected, 2, 2}} = Network.echo(addr, called_ae_title: "SCP")
      Association.release(held)
    end

    test "reports a storage directory it can't create", %{dir: dir} do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "file"), "")

      assert {:error, "couldn't start the listener: {:storage_directory, " <> _} =
               Storescp.start(["-od", Path.join([dir, "file", "under"]), "0"])
    end
  end

  describe "run/1" do
    test "fails without a port" do
      assert catch_exit(Storescp.run([])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, ["expected the port to listen on" <> _]}
    end

    test "fails on a port that isn't one" do
      for port <- ["http", "70000"] do
        assert catch_exit(Storescp.run([port])) == {:shutdown, 1}
        assert_received {:mix_shell, :error, ["invalid port " <> _]}
      end
    end

    test "fails on an unknown option" do
      assert catch_exit(Storescp.run(["--bogus", "0"])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, ["unknown option --bogus"]}
    end
  end

  defp open(addr) do
    Association.request(addr,
      called_ae_title: "SCP",
      presentation_contexts: [
        %{
          abstract_syntax: @ct_image_storage,
          transfer_syntaxes: [TransferSyntax.implicit_vr_little_endian()]
        }
      ],
      timeout: 5_000
    )
  end

  # Sends one C-STORE and returns the C-STORE-RSP status
  defp store(addr, uid, opts \\ []) do
    {:ok, assoc} = open(addr)
    {:ok, pc} = Association.accepted_context(assoc, @ct_image_storage)
    data = ImplicitVR.encode(DataSet.put_element(DataSet.new(), {0x0010, 0x0020}, :LO, "PID-1"))

    :ok =
      Association.send_pdata(
        assoc,
        pc.id,
        true,
        DIMSE.build_cstore_rq(@ct_image_storage, uid, 1, opts)
      )

    :ok = Association.send_pdata(assoc, pc.id, false, data)
    {:ok, {:p_data, [pdv]}} = Association.receive_pdu(assoc, 5_000)
    {:ok, rsp} = DIMSE.decode_command(pdv.data)
    Association.release(assoc)
    rsp.status
  end
end
