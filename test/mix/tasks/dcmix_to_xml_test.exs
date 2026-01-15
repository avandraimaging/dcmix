defmodule Mix.Tasks.Dcmix.ToXmlTest do
  use ExUnit.Case, async: false

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "0_ORIGINAL.dcm")

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    test "converts DICOM to XML and outputs to stdout" do
      Mix.Tasks.Dcmix.ToXml.run([@valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      assert output =~ "<?xml"
      assert output =~ "NativeDicomModel"
    end

    test "converts with pretty printing by default" do
      Mix.Tasks.Dcmix.ToXml.run([@valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      # Pretty printed XML has newlines
      assert output =~ "\n"
    end

    test "converts with --no-pretty option" do
      Mix.Tasks.Dcmix.ToXml.run(["--no-pretty", @valid_dcm])

      assert_received {:mix_shell, :info, [output]}
      assert output =~ "<?xml"
      assert output =~ "NativeDicomModel"
    end

    test "writes to output file when specified" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.xml")

      try do
        Mix.Tasks.Dcmix.ToXml.run([@valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
        assert message =~ tmp_file

        assert File.exists?(tmp_file)
        content = File.read!(tmp_file)
        assert content =~ "<?xml"
        assert content =~ "NativeDicomModel"
      after
        File.rm(tmp_file)
      end
    end

    test "writes non-pretty XML to output file with --no-pretty" do
      tmp_file = Path.join(System.tmp_dir!(), "nopretty_#{:rand.uniform(100_000)}.xml")

      try do
        Mix.Tasks.Dcmix.ToXml.run(["--no-pretty", @valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        content = File.read!(tmp_file)
        assert content =~ "<?xml"
      after
        File.rm(tmp_file)
      end
    end

    test "shows error when no file provided" do
      assert catch_exit(Mix.Tasks.Dcmix.ToXml.run([])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Usage:"
    end

    test "shows error when file not found" do
      assert catch_exit(Mix.Tasks.Dcmix.ToXml.run(["nonexistent.dcm"])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "File not found"
    end

    test "shows error for invalid DICOM file" do
      tmp_file = Path.join(System.tmp_dir!(), "invalid_#{:rand.uniform(100_000)}.dcm")
      File.write!(tmp_file, "not a dicom file")

      try do
        assert catch_exit(Mix.Tasks.Dcmix.ToXml.run([tmp_file])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Conversion failed"
      after
        File.rm(tmp_file)
      end
    end
  end
end
