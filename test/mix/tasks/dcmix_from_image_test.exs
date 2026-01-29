defmodule Mix.Tasks.Dcmix.FromImageTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Dcmix.FromImage
  alias Dcmix.DataSet

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "nema_mr_brain_512x512.dcm")

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp create_minimal_png do
    # PNG signature
    signature = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>

    # IHDR chunk: 2x2, 8-bit, RGB (color type 2)
    ihdr_data = <<0, 0, 0, 2, 0, 0, 0, 2, 8, 2, 0, 0, 0>>
    ihdr_crc = :erlang.crc32(<<"IHDR", ihdr_data::binary>>)
    ihdr = <<13::32, "IHDR", ihdr_data::binary, ihdr_crc::32>>

    # IDAT chunk
    raw_data = <<0, 255, 0, 0, 0, 255, 0, 0, 0, 0, 255, 255, 255, 255>>
    compressed = :zlib.compress(raw_data)
    idat_crc = :erlang.crc32(<<"IDAT", compressed::binary>>)
    idat = <<byte_size(compressed)::32, "IDAT", compressed::binary, idat_crc::32>>

    # IEND chunk
    iend_crc = :erlang.crc32("IEND")
    iend = <<0::32, "IEND", iend_crc::32>>

    signature <> ihdr <> idat <> iend
  end

  describe "run/1" do
    test "converts PNG to DICOM file" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run([tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
        assert message =~ tmp_dcm

        assert File.exists?(tmp_dcm)

        # Verify the output is valid DICOM
        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        # Rows
        assert DataSet.get_value(dataset, {0x0028, 0x0010}) == 2
        # Columns
        assert DataSet.get_value(dataset, {0x0028, 0x0011}) == 2
        assert DataSet.get_string(dataset, {0x0028, 0x0004}) == "RGB"
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "converts with --dataset-from option" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["--dataset-from", @valid_dcm, tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, original} = Dcmix.read_file(@valid_dcm)
        {:ok, dataset} = Dcmix.read_file(tmp_dcm)

        # Patient info should be from template
        assert DataSet.get_string(dataset, {0x0010, 0x0010}) ==
                 DataSet.get_string(original, {0x0010, 0x0010})
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "supports -d alias for --dataset-from" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["-d", @valid_dcm, tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, original} = Dcmix.read_file(@valid_dcm)
        {:ok, dataset} = Dcmix.read_file(tmp_dcm)

        assert DataSet.get_string(dataset, {0x0010, 0x0010}) ==
                 DataSet.get_string(original, {0x0010, 0x0010})
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "converts with --study-from option" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["--study-from", @valid_dcm, tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, original} = Dcmix.read_file(@valid_dcm)
        {:ok, dataset} = Dcmix.read_file(tmp_dcm)

        # Patient and study info should be copied
        assert DataSet.get_string(dataset, {0x0010, 0x0010}) ==
                 DataSet.get_string(original, {0x0010, 0x0010})

        assert DataSet.get_string(dataset, {0x0020, 0x000D}) ==
                 DataSet.get_string(original, {0x0020, 0x000D})
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "supports -s alias for --study-from" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["-s", @valid_dcm, tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "converts with --series-from option" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["--series-from", @valid_dcm, tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, original} = Dcmix.read_file(@valid_dcm)
        {:ok, dataset} = Dcmix.read_file(tmp_dcm)

        # Patient, study, and series info should be copied
        assert DataSet.get_string(dataset, {0x0020, 0x000E}) ==
                 DataSet.get_string(original, {0x0020, 0x000E})
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "supports -e alias for --series-from" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["-e", @valid_dcm, tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "converts with --sop-class secondary_capture" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["--sop-class", "secondary_capture", tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        assert DataSet.get_string(dataset, {0x0008, 0x0016}) == "1.2.840.10008.5.1.4.1.1.7"
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "converts with --sop-class vl_photo" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["--sop-class", "vl_photo", tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        assert DataSet.get_string(dataset, {0x0008, 0x0016}) == "1.2.840.10008.5.1.4.1.1.77.1.4"
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "supports -c alias for --sop-class" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["-c", "vl_photo", tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        assert DataSet.get_string(dataset, {0x0008, 0x0016}) == "1.2.840.10008.5.1.4.1.1.77.1.4"
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "converts with --no-type2 option" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["--no-type2", tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        # Type 2 attributes should not be inserted
        refute DataSet.has_tag?(dataset, {0x0010, 0x0010})
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "converts with --no-type1 option" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_png, create_minimal_png())

      try do
        FromImage.run(["--no-type1", tmp_png, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        # SOPInstanceUID should not be auto-generated
        refute DataSet.has_tag?(dataset, {0x0008, 0x0018})
      after
        File.rm(tmp_png)
        File.rm(tmp_dcm)
      end
    end

    test "shows error when no files provided" do
      assert catch_exit(FromImage.run([])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Usage:"
    end

    test "shows error when only one file provided" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      File.write!(tmp_png, create_minimal_png())

      try do
        assert catch_exit(FromImage.run([tmp_png])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Usage:"
      after
        File.rm(tmp_png)
      end
    end

    test "shows error when input file not found" do
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      assert catch_exit(FromImage.run(["nonexistent.png", tmp_dcm])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "File not found"
    end

    test "shows error when dataset-from file not found" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")
      File.write!(tmp_png, create_minimal_png())

      try do
        assert catch_exit(FromImage.run(["-d", "nonexistent.dcm", tmp_png, tmp_dcm])) ==
                 {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Failed to read"
      after
        File.rm(tmp_png)
      end
    end

    test "shows error for unknown SOP class" do
      tmp_png = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")
      File.write!(tmp_png, create_minimal_png())

      try do
        assert catch_exit(FromImage.run(["--sop-class", "unknown_class", tmp_png, tmp_dcm])) ==
                 {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Unknown SOP class"
      after
        File.rm(tmp_png)
      end
    end

    test "shows error for invalid image file" do
      tmp_png = Path.join(System.tmp_dir!(), "invalid_#{:rand.uniform(100_000)}.png")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")
      File.write!(tmp_png, "not a valid image")

      try do
        assert catch_exit(FromImage.run([tmp_png, tmp_dcm])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Conversion failed"
      after
        File.rm(tmp_png)
      end
    end
  end
end
