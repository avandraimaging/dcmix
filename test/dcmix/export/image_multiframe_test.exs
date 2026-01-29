defmodule Dcmix.Export.ImageMultiframeTest do
  @moduledoc """
  Tests for exporting multi-frame DICOM images to separate files.
  """
  use ExUnit.Case, async: true

  alias Dcmix.Export.Image

  @fixtures_path "test/fixtures"
  @multiframe_3 Path.join(@fixtures_path, "nema_mr_knee_multiframe_3.dcm")
  @multiframe_11 Path.join(@fixtures_path, "nema_mr_perfusion_multiframe_11.dcm")
  @single_frame Path.join(@fixtures_path, "nema_mr_brain_512x512.dcm")

  describe "to_files/3 with multi-frame images" do
    test "exports all frames from 3-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%04d.png")
        {:ok, paths} = Image.to_files(dataset, pattern)

        assert length(paths) == 3
        assert Enum.all?(paths, &File.exists?/1)

        # Verify file names
        assert Path.basename(Enum.at(paths, 0)) == "frame_0000.png"
        assert Path.basename(Enum.at(paths, 1)) == "frame_0001.png"
        assert Path.basename(Enum.at(paths, 2)) == "frame_0002.png"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "exports all frames from 11-frame image" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_11)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "perf_%02d.png")
        {:ok, paths} = Image.to_files(dataset, pattern)

        assert length(paths) == 11
        assert Enum.all?(paths, &File.exists?/1)

        # Verify numbering
        assert Path.basename(Enum.at(paths, 0)) == "perf_00.png"
        assert Path.basename(Enum.at(paths, 10)) == "perf_10.png"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "exports specific frames only" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_11)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, paths} = Image.to_files(dataset, pattern, frames: [0, 5, 10])

        assert length(paths) == 3
        assert Enum.all?(paths, &File.exists?/1)

        assert Path.basename(Enum.at(paths, 0)) == "frame_0.png"
        assert Path.basename(Enum.at(paths, 1)) == "frame_5.png"
        assert Path.basename(Enum.at(paths, 2)) == "frame_10.png"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for invalid frame indices" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%d.png")
        result = Image.to_files(dataset, pattern, frames: [0, 99])

        assert {:error, {:invalid_frames, _}} = result
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "exports single-frame image to one file" do
      {:ok, dataset} = Dcmix.read_file(@single_frame)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%04d.png")
        {:ok, paths} = Image.to_files(dataset, pattern)

        assert length(paths) == 1
        assert File.exists?(hd(paths))
        assert Path.basename(hd(paths)) == "frame_0000.png"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "exports to PGM format" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%d.pgm")
        {:ok, paths} = Image.to_files(dataset, pattern)

        assert length(paths) == 3
        assert Enum.all?(paths, &File.exists?/1)

        # Verify PGM magic number
        {:ok, content} = File.read(hd(paths))
        assert String.starts_with?(content, "P5")
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "each exported frame has different content" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%d.png")
        {:ok, paths} = Image.to_files(dataset, pattern)

        contents = Enum.map(paths, fn p -> File.read!(p) end)

        # Frames should be different
        [c0, c1, c2] = contents
        refute c0 == c1
        refute c1 == c2
        refute c0 == c2
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "Dcmix.to_images/3 high-level API" do
    test "exports all frames via main module" do
      {:ok, dataset} = Dcmix.read_file(@multiframe_3)
      tmp_dir = create_tmp_dir()

      try do
        pattern = Path.join(tmp_dir, "frame_%04d.png")
        {:ok, paths} = Dcmix.to_images(dataset, pattern)

        assert length(paths) == 3
        assert Enum.all?(paths, &File.exists?/1)
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  defp create_tmp_dir do
    dir = Path.join(System.tmp_dir!(), "dcmix_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(dir)
    dir
  end
end
