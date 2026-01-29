defmodule Mix.Tasks.Dcmix.ToJsonTest do
  use ExUnit.Case, async: false

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "nema_mr_brain_512x512.dcm")

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    test "converts DICOM to JSON and outputs to stdout" do
      Mix.Tasks.Dcmix.ToJson.run([@valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      assert String.starts_with?(output, "{")
      assert output =~ "00100010" or output =~ "Value"
    end

    test "converts with --pretty option" do
      Mix.Tasks.Dcmix.ToJson.run(["--pretty", @valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      # Pretty printed JSON has newlines and indentation
      assert output =~ "\n"
      assert String.starts_with?(output, "{")
    end

    test "converts with -p alias for pretty" do
      Mix.Tasks.Dcmix.ToJson.run(["-p", @valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      assert output =~ "\n"
    end

    test "writes to output file when specified" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.json")

      try do
        Mix.Tasks.Dcmix.ToJson.run([@valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
        assert message =~ tmp_file

        assert File.exists?(tmp_file)
        content = File.read!(tmp_file)
        assert String.starts_with?(content, "{")
      after
        File.rm(tmp_file)
      end
    end

    test "writes pretty JSON to output file" do
      tmp_file = Path.join(System.tmp_dir!(), "pretty_#{:rand.uniform(100_000)}.json")

      try do
        Mix.Tasks.Dcmix.ToJson.run(["--pretty", @valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        content = File.read!(tmp_file)
        assert content =~ "\n"
      after
        File.rm(tmp_file)
      end
    end

    test "shows error when no file provided" do
      assert catch_exit(Mix.Tasks.Dcmix.ToJson.run([])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Usage:"
    end

    test "shows error when file not found" do
      assert catch_exit(Mix.Tasks.Dcmix.ToJson.run(["nonexistent.dcm"])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "File not found"
    end

    test "shows error for invalid DICOM file" do
      tmp_file = Path.join(System.tmp_dir!(), "invalid_#{:rand.uniform(100_000)}.dcm")
      File.write!(tmp_file, "not a dicom file")

      try do
        assert catch_exit(Mix.Tasks.Dcmix.ToJson.run([tmp_file])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Conversion failed"
      after
        File.rm(tmp_file)
      end
    end
  end
end
