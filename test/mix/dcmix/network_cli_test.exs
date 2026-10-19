defmodule Mix.Dcmix.NetworkCLITest do
  use ExUnit.Case, async: true

  alias Mix.Dcmix.NetworkCLI

  doctest Mix.Dcmix.NetworkCLI

  describe "parse/2" do
    test "reads the task's own switches and the -k, -P and -S aliases" do
      assert NetworkCLI.parse(["-k", "PatientID=1", "-k", "StudyDate=", "-P", "h", "1"],
               key: :keep,
               patient: :boolean
             ) == {:ok, [key: "PatientID=1", key: "StudyDate=", patient: true], ["h", "1"]}
    end

    test "reports an option given a value of the wrong type" do
      assert NetworkCLI.parse(["-to", "soon", "h", "1"]) ==
               {:error, "invalid value \"soon\" for --timeout"}
    end
  end

  describe "peer/1" do
    test "refuses a port that isn't a number" do
      assert NetworkCLI.peer(["pacs", "http"]) == {:error, "invalid port \"http\""}
    end
  end

  describe "connection_opts/1" do
    test "prefers the ACSE timeout to --timeout, and passes the PDU length and verbose" do
      assert NetworkCLI.connection_opts(
               timeout: 5,
               acse_timeout: 10,
               max_pdu: 32_768,
               verbose: true
             ) ==
               [timeout: 10_000, max_pdu_length: 32_768, verbose: true]
    end
  end

  describe "identifier/1" do
    test "keeps a value containing =" do
      assert {:ok, ds} = NetworkCLI.identifier(["PatientName=A=B"])
      assert Dcmix.DataSet.get_string(ds, {0x0010, 0x0010}) == "A=B"
    end

    test "refuses a tag that isn't in the dictionary" do
      assert NetworkCLI.identifier(["(0009,0010)=X"]) == {:error, "unknown key (0009,0010)"}
    end
  end

  describe "status/1" do
    test "reads none for a missing status" do
      assert NetworkCLI.status(nil) == "none"
    end
  end
end
