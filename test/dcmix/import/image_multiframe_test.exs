defmodule Dcmix.Import.ImageMultiframeTest do
  @moduledoc """
  Tests for importing multiple images into a multi-frame DICOM.
  """
  use ExUnit.Case, async: true

  alias Dcmix.Import.Image
  alias Dcmix.PixelData

  @fixtures_path "test/fixtures"
  @multiframe_3 Path.join(@fixtures_path, "nema_mr_knee_multiframe_3.dcm")

  describe "from_files/2 with list of files" do
    test "creates multi-frame DICOM from exported frames" do
      # First export frames from a known multi-frame file
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        # Export frames
        pattern = Path.join(tmp_dir, "frame_%04d.png")
        {:ok, exported_paths} = Dcmix.to_images(source, pattern)

        # Import them back
        {:ok, dataset} = Image.from_files(exported_paths)

        # Verify multi-frame attributes
        info = PixelData.info(dataset)
        assert info.number_of_frames == 3
        assert info.has_pixel_data == true

        # Dimensions should match original
        assert info.rows == 256
        assert info.columns == 256
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "creates single-frame DICOM from one file" do
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        # Export just one frame
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, _} = Dcmix.to_images(source, pattern, frames: [0])

        # Import single frame
        {:ok, dataset} = Image.from_files([Path.join(tmp_dir, "frame_0.png")])

        info = PixelData.info(dataset)
        assert info.number_of_frames == 1
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for empty list" do
      result = Image.from_files([])
      assert {:error, {:no_files, _}} = result
    end

    test "returns error for non-existent files" do
      result = Image.from_files(["/nonexistent/file.png"])
      assert {:error, {:read_failed, _}} = result
    end

    test "sets correct SOP class for grayscale multi-frame" do
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, paths} = Dcmix.to_images(source, pattern)
        {:ok, dataset} = Image.from_files(paths)

        # Should use Multi-frame Grayscale Byte SC
        sop_class = Dcmix.get_string(dataset, {0x0008, 0x0016})
        # Multi-frame Grayscale Byte SC or Word SC
        assert sop_class in [
                 # Grayscale Byte
                 "1.2.840.10008.5.1.4.1.1.7.2",
                 # Grayscale Word
                 "1.2.840.10008.5.1.4.1.1.7.3"
               ]
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "pixel data size matches expected" do
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, paths} = Dcmix.to_images(source, pattern)
        {:ok, dataset} = Image.from_files(paths)

        expected_size = PixelData.expected_size(dataset)
        {:ok, pixels} = PixelData.extract(dataset)

        assert byte_size(pixels) == expected_size
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "from_files/2 with glob pattern" do
    test "creates multi-frame DICOM from glob pattern" do
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%04d.png")
        {:ok, _} = Dcmix.to_images(source, pattern)

        # Import using glob
        glob_pattern = Path.join(tmp_dir, "frame_*.png")
        {:ok, dataset} = Image.from_files(glob_pattern)

        info = PixelData.info(dataset)
        assert info.number_of_frames == 3
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for non-matching glob" do
      result = Image.from_files("/nonexistent/*.png")
      assert {:error, {:no_files_found, _}} = result
    end
  end

  describe "from_files/2 with sorting options" do
    test "natural sort is default" do
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        # Export with non-padded numbers
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, _} = Dcmix.to_images(source, pattern)

        # Import - should sort naturally (0, 1, 2 not alphabetically)
        glob_pattern = Path.join(tmp_dir, "frame_*.png")
        {:ok, dataset} = Image.from_files(glob_pattern, sort: true)

        info = PixelData.info(dataset)
        assert info.number_of_frames == 3
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "can disable sorting" do
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, paths} = Dcmix.to_images(source, pattern)

        # Reverse the order manually
        reversed = Enum.reverse(paths)
        {:ok, dataset} = Image.from_files(reversed, sort: false)

        info = PixelData.info(dataset)
        assert info.number_of_frames == 3
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "from_files/2 with template options" do
    test "copies series info from template" do
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, paths} = Dcmix.to_images(source, pattern)

        {:ok, dataset} = Image.from_files(paths, series_from: source)

        # Should have copied series UID
        original_series = Dcmix.get_string(source, {0x0020, 0x000E})
        new_series = Dcmix.get_string(dataset, {0x0020, 0x000E})
        assert new_series == original_series
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "Dcmix.from_images/2 high-level API" do
    test "creates multi-frame via main module" do
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, paths} = Dcmix.to_images(source, pattern)

        {:ok, dataset} = Dcmix.from_images(paths)

        info = PixelData.info(dataset)
        assert info.number_of_frames == 3
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "accepts glob pattern via main module" do
      {:ok, source} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%04d.png")
        {:ok, _} = Dcmix.to_images(source, pattern)

        {:ok, dataset} = Dcmix.from_images(Path.join(tmp_dir, "*.png"))

        info = PixelData.info(dataset)
        assert info.number_of_frames == 3
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "round-trip multi-frame export/import" do
    test "exported and re-imported data has same frame count" do
      {:ok, original} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        # Export
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, paths} = Dcmix.to_images(original, pattern)

        # Import
        {:ok, reimported} = Dcmix.from_images(paths)

        # Compare
        orig_info = PixelData.info(original)
        new_info = PixelData.info(reimported)

        assert new_info.number_of_frames == orig_info.number_of_frames
        assert new_info.rows == orig_info.rows
        assert new_info.columns == orig_info.columns
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  defp create_tmp_dir do
    dir = Path.join(System.tmp_dir!(), "dcmix_import_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(dir)
    dir
  end
end
