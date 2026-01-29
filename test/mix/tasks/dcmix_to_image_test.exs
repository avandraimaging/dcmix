defmodule Mix.Tasks.Dcmix.ToImageTest do
  use ExUnit.Case, async: false

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "nema_mr_cardiac_256x256.dcm")

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    test "converts DICOM to PNG" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")

      try do
        Mix.Tasks.Dcmix.ToImage.run([@valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
        assert message =~ tmp_file

        assert File.exists?(tmp_file)
        # Check PNG magic bytes
        content = File.read!(tmp_file)
        assert <<0x89, "PNG", _::binary>> = content
      after
        File.rm(tmp_file)
      end
    end

    test "converts DICOM to PGM" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.pgm")

      try do
        Mix.Tasks.Dcmix.ToImage.run([@valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        assert File.exists?(tmp_file)
        content = File.read!(tmp_file)
        assert String.starts_with?(content, "P5\n")
      after
        File.rm(tmp_file)
      end
    end

    test "supports --frame option" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")

      try do
        Mix.Tasks.Dcmix.ToImage.run(["--frame", "0", @valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
        assert File.exists?(tmp_file)
      after
        File.rm(tmp_file)
      end
    end

    test "supports -f alias for frame" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")

      try do
        Mix.Tasks.Dcmix.ToImage.run(["-f", "0", @valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
      after
        File.rm(tmp_file)
      end
    end

    test "supports --window auto option" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")

      try do
        Mix.Tasks.Dcmix.ToImage.run(["--window", "auto", @valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
      after
        File.rm(tmp_file)
      end
    end

    test "supports --window min_max option" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")

      try do
        Mix.Tasks.Dcmix.ToImage.run(["--window", "min_max", @valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
      after
        File.rm(tmp_file)
      end
    end

    test "supports --window center,width option" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")

      try do
        Mix.Tasks.Dcmix.ToImage.run(["--window", "512,256", @valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
      after
        File.rm(tmp_file)
      end
    end

    test "supports -w alias for window" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")

      try do
        Mix.Tasks.Dcmix.ToImage.run(["-w", "auto", @valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
      after
        File.rm(tmp_file)
      end
    end

    test "supports --format option" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.raw")

      try do
        Mix.Tasks.Dcmix.ToImage.run(["--format", "pgm", @valid_dcm, tmp_file])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        content = File.read!(tmp_file)
        assert String.starts_with?(content, "P5\n")
      after
        File.rm(tmp_file)
      end
    end

    test "shows error when no files provided" do
      assert catch_exit(Mix.Tasks.Dcmix.ToImage.run([])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Usage:"
    end

    test "shows error when only input file provided" do
      assert catch_exit(Mix.Tasks.Dcmix.ToImage.run([@valid_dcm])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Usage:"
    end

    test "shows error when file not found" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")

      assert catch_exit(Mix.Tasks.Dcmix.ToImage.run(["nonexistent.dcm", tmp_file])) ==
               {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "File not found"
    end

    test "shows error for invalid window specification" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")

      assert catch_exit(
               Mix.Tasks.Dcmix.ToImage.run(["--window", "invalid", @valid_dcm, tmp_file])
             ) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Invalid window"
    end

    test "shows error for unknown format" do
      tmp_file = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.raw")

      assert catch_exit(
               Mix.Tasks.Dcmix.ToImage.run(["--format", "bmp", @valid_dcm, tmp_file])
             ) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Unknown format"
    end

    test "shows error for invalid DICOM file" do
      tmp_dcm = Path.join(System.tmp_dir!(), "invalid_#{:rand.uniform(100_000)}.dcm")
      tmp_out = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.png")
      File.write!(tmp_dcm, "not a dicom file")

      try do
        assert catch_exit(Mix.Tasks.Dcmix.ToImage.run([tmp_dcm, tmp_out])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Conversion failed" or message =~ "Error"
      after
        File.rm(tmp_dcm)
        File.rm(tmp_out)
      end
    end
  end
end
