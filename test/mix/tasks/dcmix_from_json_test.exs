defmodule Mix.Tasks.Dcmix.FromJsonTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Dcmix.FromJson

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "0_ORIGINAL.dcm")

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp create_test_json do
    """
    {
      "00100010": {"vr": "PN", "Value": [{"Alphabetic": "Test^Patient"}]},
      "00100020": {"vr": "LO", "Value": ["TESTID123"]},
      "00080060": {"vr": "CS", "Value": ["CT"]}
    }
    """
  end

  describe "run/1" do
    test "converts JSON to DICOM file" do
      tmp_json = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.json")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_json, create_test_json())

      try do
        FromJson.run([tmp_json, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
        assert message =~ tmp_dcm

        assert File.exists?(tmp_dcm)

        # Verify the output is valid DICOM
        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        assert Dcmix.DataSet.get_string(dataset, {0x0010, 0x0010}) == "Test^Patient"
        assert Dcmix.DataSet.get_string(dataset, {0x0010, 0x0020}) == "TESTID123"
      after
        File.rm(tmp_json)
        File.rm(tmp_dcm)
      end
    end

    test "converts JSON with template DICOM" do
      tmp_json = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.json")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      # JSON that only updates patient name
      json = """
      {
        "00100010": {"vr": "PN", "Value": [{"Alphabetic": "New^Name"}]}
      }
      """
      File.write!(tmp_json, json)

      try do
        FromJson.run(["--template", @valid_dcm, tmp_json, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        # Verify the output has merged data
        {:ok, original} = Dcmix.read_file(@valid_dcm)
        {:ok, dataset} = Dcmix.read_file(tmp_dcm)

        # Name should be from JSON
        assert Dcmix.DataSet.get_string(dataset, {0x0010, 0x0010}) == "New^Name"

        # Study UID should be from template
        assert Dcmix.DataSet.get_string(dataset, {0x0020, 0x000D}) ==
                 Dcmix.DataSet.get_string(original, {0x0020, 0x000D})
      after
        File.rm(tmp_json)
        File.rm(tmp_dcm)
      end
    end

    test "supports -t alias for --template" do
      tmp_json = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.json")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      json = """
      {
        "00100010": {"vr": "PN", "Value": [{"Alphabetic": "Alias^Test"}]}
      }
      """
      File.write!(tmp_json, json)

      try do
        FromJson.run(["-t", @valid_dcm, tmp_json, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        assert Dcmix.DataSet.get_string(dataset, {0x0010, 0x0010}) == "Alias^Test"
      after
        File.rm(tmp_json)
        File.rm(tmp_dcm)
      end
    end

    test "shows error when no files provided" do
      assert catch_exit(FromJson.run([])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Usage:"
    end

    test "shows error when only one file provided" do
      tmp_json = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.json")
      File.write!(tmp_json, create_test_json())

      try do
        assert catch_exit(FromJson.run([tmp_json])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Usage:"
      after
        File.rm(tmp_json)
      end
    end

    test "shows error when input file not found" do
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      assert catch_exit(FromJson.run(["nonexistent.json", tmp_dcm])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "File not found"
    end

    test "shows error when template file not found" do
      tmp_json = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.json")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")
      File.write!(tmp_json, create_test_json())

      try do
        assert catch_exit(FromJson.run(["-t", "nonexistent.dcm", tmp_json, tmp_dcm])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Failed to read template"
      after
        File.rm(tmp_json)
      end
    end

    test "shows error for invalid JSON file" do
      tmp_json = Path.join(System.tmp_dir!(), "invalid_#{:rand.uniform(100_000)}.json")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")
      File.write!(tmp_json, "not valid json {{{")

      try do
        assert catch_exit(FromJson.run([tmp_json, tmp_dcm])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Conversion failed"
      after
        File.rm(tmp_json)
      end
    end
  end
end
