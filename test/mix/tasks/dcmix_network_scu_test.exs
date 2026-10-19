defmodule Mix.Tasks.Dcmix.NetworkSCUTest do
  # Mix.shell/1 is global
  use ExUnit.Case, async: false

  alias Dcmix.Network.Listener
  alias Mix.Tasks.Dcmix.{Echoscu, Findscu, Getscu, Movescu}

  @moduletag capture_log: true

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp start_listener do
    listener = start_supervised!({Listener, port: 0, ae_title: "SCP"})
    {:ok, port} = Listener.port(listener)
    Integer.to_string(port)
  end

  # Runs a task expected to fail, returning the error it printed
  defp failure(task, args) do
    assert catch_exit(task.run(args)) == {:shutdown, 1}
    assert_received {:mix_shell, :error, [message]}
    message
  end

  describe "mix dcmix.echoscu" do
    test "reports success, with dcmtk's flags" do
      Echoscu.run(["-aet", "ME", "-aec", "SCP", "-to", "5", "localhost", start_listener()])

      assert_received {:mix_shell, :info, ["C-ECHO to localhost:" <> rest]}
      assert rest =~ ": success"
    end

    test "fails when the node rejects the association" do
      assert failure(Echoscu, ["-aec", "OTHER", "localhost", start_listener()]) =~
               "{:association_rejected, 1, 7}"
    end

    test "fails without a peer and port" do
      assert failure(Echoscu, ["localhost"]) =~ "expected the peer and port"
    end

    test "fails on an unknown option" do
      assert failure(Echoscu, ["--bogus", "localhost", "104"]) == "unknown option --bogus"
    end
  end

  describe "mix dcmix.findscu" do
    test "refuses the Patient Root model" do
      assert failure(Findscu, ["-P", "localhost", "104"]) =~ "Study Root model only"
    end

    test "refuses an unknown key" do
      assert failure(Findscu, ["-k", "Nope=1", "localhost", "104"]) == "unknown key Nope"
    end

    test "reports a failed query" do
      assert failure(Findscu, ["-k", "QueryRetrieveLevel=STUDY", "localhost", "1"]) =~
               "C-FIND to localhost:1 failed: {:connection_failed"
    end
  end

  describe "mix dcmix.getscu" do
    test "refuses a key without a value" do
      assert failure(Getscu, ["-k", "PatientID", "localhost", "104"]) =~ "expected a key"
    end

    test "reports a failed retrieve" do
      assert failure(Getscu, ["-k", "QueryRetrieveLevel=STUDY", "localhost", "1"]) =~
               "C-GET to localhost:1 failed: {:connection_failed"
    end
  end

  describe "mix dcmix.movescu" do
    test "reports a failed move" do
      assert failure(Movescu, ["-k", "QueryRetrieveLevel=STUDY", "-aem", "DEST", "localhost", "1"]) =~
               "C-MOVE to localhost:1 failed: {:connection_failed"
    end

    test "refuses an invalid destination before connecting" do
      assert failure(Movescu, ["-aem", String.duplicate("A", 17), "localhost", "1"]) =~
               "invalid_destination_ae_title"
    end
  end
end
