defmodule Dcmix.PixelData.MultiFrameTest do
  @moduledoc """
  Tests for multi-frame DICOM image handling using NEMA test fixtures.

  These tests verify that dcmix correctly handles multi-frame images,
  including parsing frame counts, calculating expected sizes, and
  extracting/exporting individual frames.
  """
  use ExUnit.Case, async: true

  alias Dcmix.PixelData

  @fixtures_path "test/fixtures"
  @multiframe_3 Path.join(@fixtures_path, "nema_mr_knee_multiframe_3.dcm")
  @multiframe_11 Path.join(@fixtures_path, "nema_mr_perfusion_multiframe_11.dcm")
  @single_frame Path.join(@fixtures_path, "nema_mr_brain_512x512.dcm")

  describe "PixelData.info/1 with multi-frame images" do
    test "reports correct number_of_frames for 3-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      info = PixelData.info(dataset)

      assert info.number_of_frames == 3
      assert info.rows == 256
      assert info.columns == 256
      assert info.bits_allocated == 16
      assert info.has_pixel_data == true
      assert info.encapsulated == false
    end

    test "reports correct number_of_frames for 11-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_11)

      info = PixelData.info(dataset)

      assert info.number_of_frames == 11
      assert info.rows == 128
      assert info.columns == 128
      assert info.bits_allocated == 16
      assert info.has_pixel_data == true
      assert info.encapsulated == false
    end

    test "reports number_of_frames as 1 for single-frame image" do
      {:ok, dataset} = Dcmix.read_file(@single_frame)

      info = PixelData.info(dataset)

      assert info.number_of_frames == 1
      assert info.rows == 512
      assert info.columns == 512
    end
  end

  describe "PixelData.expected_size/1 with multi-frame images" do
    test "calculates correct size for 3-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      expected = PixelData.expected_size(dataset)

      # 256 x 256 x 3 frames x 2 bytes (16-bit) x 1 sample
      assert expected == 256 * 256 * 3 * 2
      assert expected == 393_216
    end

    test "calculates correct size for 11-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_11)

      expected = PixelData.expected_size(dataset)

      # 128 x 128 x 11 frames x 2 bytes (16-bit) x 1 sample
      assert expected == 128 * 128 * 11 * 2
      assert expected == 360_448
    end

    test "calculates correct size for single-frame image" do
      {:ok, dataset} = Dcmix.read_file(@single_frame)

      expected = PixelData.expected_size(dataset)

      # 512 x 512 x 2 bytes (16-bit) - single frame
      assert expected == 512 * 512 * 2
      assert expected == 524_288
    end
  end

  describe "PixelData.extract/1 with multi-frame images" do
    test "extracts all pixel data from 3-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      {:ok, pixel_data} = PixelData.extract(dataset)

      expected_size = PixelData.expected_size(dataset)
      assert byte_size(pixel_data) == expected_size
    end

    test "extracts all pixel data from 11-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_11)

      {:ok, pixel_data} = PixelData.extract(dataset)

      expected_size = PixelData.expected_size(dataset)
      assert byte_size(pixel_data) == expected_size
    end

    test "pixel data contains valid 16-bit values" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      {:ok, pixel_data} = PixelData.extract(dataset)

      # Sample some pixels to verify they're valid 16-bit values
      <<first_pixel::16-little, _rest::binary>> = pixel_data
      assert first_pixel >= 0 and first_pixel <= 65_535
    end
  end

  describe "frame extraction helpers" do
    test "can calculate individual frame size" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      info = PixelData.info(dataset)
      frame_size = info.rows * info.columns * div(info.bits_allocated, 8) * info.samples_per_pixel

      # 256 x 256 x 2 bytes = 131072 bytes per frame
      assert frame_size == 131_072
    end

    test "can manually extract individual frames from native data" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      {:ok, pixel_data} = PixelData.extract(dataset)
      info = PixelData.info(dataset)

      frame_size = info.rows * info.columns * div(info.bits_allocated, 8) * info.samples_per_pixel

      # Extract frame 0
      <<frame0::binary-size(frame_size), _rest::binary>> = pixel_data
      assert byte_size(frame0) == frame_size

      # Extract frame 1
      <<_skip::binary-size(frame_size), frame1::binary-size(frame_size), _rest::binary>> =
        pixel_data

      assert byte_size(frame1) == frame_size

      # Extract frame 2 (last frame)
      offset = frame_size * 2
      <<_skip::binary-size(offset), frame2::binary>> = pixel_data
      assert byte_size(frame2) == frame_size

      # Frames should be different (not all zeros or identical)
      refute frame0 == frame1
      refute frame1 == frame2
    end

    test "all frames together equal total pixel data" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_11)

      {:ok, pixel_data} = PixelData.extract(dataset)
      info = PixelData.info(dataset)

      frame_size = info.rows * info.columns * div(info.bits_allocated, 8) * info.samples_per_pixel
      total_size = frame_size * info.number_of_frames

      assert byte_size(pixel_data) == total_size
    end
  end

  describe "image export with frame option" do
    test "exports first frame from multi-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      tmp_path = Path.join(System.tmp_dir!(), "frame_0_test.png")

      try do
        assert :ok = Dcmix.to_image(dataset, tmp_path, frame: 0)
        assert File.exists?(tmp_path)

        {:ok, stat} = File.stat(tmp_path)
        assert stat.size > 0
      after
        File.rm(tmp_path)
      end
    end

    test "exports middle frame from multi-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      tmp_path = Path.join(System.tmp_dir!(), "frame_1_test.png")

      try do
        assert :ok = Dcmix.to_image(dataset, tmp_path, frame: 1)
        assert File.exists?(tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "exports last frame from multi-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      tmp_path = Path.join(System.tmp_dir!(), "frame_2_test.png")

      try do
        assert :ok = Dcmix.to_image(dataset, tmp_path, frame: 2)
        assert File.exists?(tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "returns error for frame index out of bounds" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)

      tmp_path = Path.join(System.tmp_dir!(), "invalid_frame_test.png")

      try do
        result = Dcmix.to_image(dataset, tmp_path, frame: 99)
        assert {:error, {:invalid_frame, _}} = result
      after
        File.rm(tmp_path)
      end
    end

    test "different frames produce different images" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_11)

      tmp_frame0 = Path.join(System.tmp_dir!(), "compare_frame_0.png")
      tmp_frame5 = Path.join(System.tmp_dir!(), "compare_frame_5.png")

      try do
        :ok = Dcmix.to_image(dataset, tmp_frame0, frame: 0)
        :ok = Dcmix.to_image(dataset, tmp_frame5, frame: 5)

        # Read files and verify they're different
        {:ok, data0} = File.read(tmp_frame0)
        {:ok, data5} = File.read(tmp_frame5)

        # Files should exist and have content
        assert byte_size(data0) > 0
        assert byte_size(data5) > 0

        # The two frames should produce different images
        # (unless the MR data happens to be identical, which is unlikely)
        refute data0 == data5
      after
        File.rm(tmp_frame0)
        File.rm(tmp_frame5)
      end
    end
  end

  describe "comparison with single-frame behavior" do
    test "single-frame image works without frame option" do
      {:ok, dataset} = Dcmix.read_file(@single_frame)

      tmp_path = Path.join(System.tmp_dir!(), "single_frame_test.png")

      try do
        assert :ok = Dcmix.to_image(dataset, tmp_path)
        assert File.exists?(tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "single-frame image works with frame: 0" do
      {:ok, dataset} = Dcmix.read_file(@single_frame)

      tmp_path = Path.join(System.tmp_dir!(), "single_frame_explicit_test.png")

      try do
        assert :ok = Dcmix.to_image(dataset, tmp_path, frame: 0)
        assert File.exists?(tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "single-frame image returns error for frame: 1" do
      {:ok, dataset} = Dcmix.read_file(@single_frame)

      tmp_path = Path.join(System.tmp_dir!(), "single_frame_invalid_test.png")

      try do
        result = Dcmix.to_image(dataset, tmp_path, frame: 1)
        assert {:error, {:invalid_frame, _}} = result
      after
        File.rm(tmp_path)
      end
    end
  end
end
