defmodule Mix.Tasks.Dcmix.DumpTest do
  use ExUnit.Case, async: false

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "0_ORIGINAL.dcm")

  setup do
    # Use process shell to capture output
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    test "dumps DICOM file to stdout" do
      Mix.Tasks.Dcmix.Dump.run([@valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      assert output =~ "PatientName" or output =~ "(0010,0010)"
    end

    test "dumps with custom max-length option" do
      Mix.Tasks.Dcmix.Dump.run(["--max-length", "128", @valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      assert is_binary(output)
    end

    test "dumps with -m alias for max-length" do
      Mix.Tasks.Dcmix.Dump.run(["-m", "32", @valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      assert is_binary(output)
    end

    test "dumps with --no-length option" do
      Mix.Tasks.Dcmix.Dump.run(["--no-length", @valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      assert is_binary(output)
    end

    test "shows error when no file provided" do
      assert catch_exit(Mix.Tasks.Dcmix.Dump.run([])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Usage:"
    end

    test "shows error when file not found" do
      assert catch_exit(Mix.Tasks.Dcmix.Dump.run(["nonexistent.dcm"])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "File not found"
    end

    test "shows error for invalid DICOM file" do
      # Create a temporary invalid file
      tmp_file = Path.join(System.tmp_dir!(), "invalid_#{:rand.uniform(100_000)}.dcm")
      File.write!(tmp_file, "not a dicom file")

      try do
        assert catch_exit(Mix.Tasks.Dcmix.Dump.run([tmp_file])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Failed to parse"
      after
        File.rm(tmp_file)
      end
    end

    test "only processes first file when multiple provided" do
      Mix.Tasks.Dcmix.Dump.run([@valid_dcm, "other.dcm"])

      assert_received {:mix_shell, :info, [output]}
      assert is_binary(output)
    end
  end
end
