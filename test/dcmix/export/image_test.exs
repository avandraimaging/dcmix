defmodule Dcmix.Export.ImageTest do
  use ExUnit.Case, async: true

  alias Dcmix.{DataSet, DataElement}
  alias Dcmix.Export.Image
  alias Dcmix.Export.Image.{Decoder, PPM}

  @fixtures_path "test/fixtures"

  describe "Decoder.get_pixel_info/1" do
    test "returns pixel info for dataset with pixel data" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "0_ORIGINAL.dcm"))

      assert {:ok, info} = Decoder.get_pixel_info(dataset)
      assert info.rows == 1760
      assert info.columns == 2140
      assert info.bits_allocated == 16
      assert info.bits_stored == 10
      assert info.samples_per_pixel == 1
      assert info.photometric_interpretation == "MONOCHROME1"
    end

    test "returns error when required fields are missing" do
      dataset = DataSet.new()

      assert {:error, {:missing_required_field, _}} = Decoder.get_pixel_info(dataset)
    end
  end

  describe "Decoder.decode/2" do
    test "decodes monochrome1 image" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "0_ORIGINAL.dcm"))

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.width == 2140
      assert decoded.height == 1760
      assert decoded.photometric == :grayscale
      assert decoded.samples_per_pixel == 1
      assert decoded.bit_depth == 8
      assert byte_size(decoded.pixels) == 2140 * 1760
    end

    test "decodes monochrome2 image" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "1_ORIGINAL.dcm"))

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.width == 2022
      assert decoded.height == 2022
      assert decoded.photometric == :grayscale
    end

    test "supports window option :min_max" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "0_ORIGINAL.dcm"))

      assert {:ok, decoded} = Decoder.decode(dataset, window: :min_max)
      assert decoded.bit_depth == 8
    end

    test "supports window option :none for 16-bit output" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "0_ORIGINAL.dcm"))

      assert {:ok, decoded} = Decoder.decode(dataset, window: :none)
      assert decoded.bit_depth == 16
      assert byte_size(decoded.pixels) == 2140 * 1760 * 2
    end

    test "supports explicit window center/width" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "0_ORIGINAL.dcm"))

      assert {:ok, decoded} = Decoder.decode(dataset, window: {512, 256})
      assert decoded.bit_depth == 8
    end

    test "returns error for encapsulated pixel data" do
      # Create a dataset with encapsulated pixel data
      dataset =
        create_minimal_image_dataset(4, 4, 8)
        |> DataSet.put(DataElement.new({0x7FE0, 0x0010}, :OB, [<<>>, <<1, 2, 3>>], :undefined))

      assert {:error, {:compressed_pixel_data, _}} = Decoder.decode(dataset)
    end

    test "returns error for invalid frame number" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "0_ORIGINAL.dcm"))

      assert {:error, {:invalid_frame, _}} = Decoder.decode(dataset, frame: 99)
    end
  end

  describe "PPM.encode/1" do
    test "encodes grayscale image to PGM format" do
      # Create a simple 2x2 grayscale image
      decoded = %{
        width: 2,
        height: 2,
        samples_per_pixel: 1,
        bit_depth: 8,
        pixels: <<100, 150, 200, 250>>,
        photometric: :grayscale
      }

      assert {:ok, binary} = PPM.encode(decoded)
      assert String.starts_with?(binary, "P5\n2 2\n255\n")
      # Header + 4 pixel bytes
      assert String.ends_with?(binary, <<100, 150, 200, 250>>)
    end

    test "encodes RGB image to PPM format" do
      # Create a simple 2x2 RGB image
      decoded = %{
        width: 2,
        height: 2,
        samples_per_pixel: 3,
        bit_depth: 8,
        pixels: <<255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255>>,
        photometric: :rgb
      }

      assert {:ok, binary} = PPM.encode(decoded)
      assert String.starts_with?(binary, "P6\n2 2\n255\n")
    end

    test "encodes 16-bit grayscale to PGM with big-endian" do
      decoded = %{
        width: 2,
        height: 2,
        samples_per_pixel: 1,
        bit_depth: 16,
        pixels: <<0, 1, 0, 2, 0, 3, 0, 4>>,
        photometric: :grayscale
      }

      assert {:ok, binary} = PPM.encode(decoded)
      assert String.starts_with?(binary, "P5\n2 2\n65535\n")
    end
  end

  describe "Image.to_file/3" do
    test "exports to PNG file" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "2_ORIGINAL.dcm"))
      tmp_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(100_000)}.png")

      try do
        assert :ok = Image.to_file(dataset, tmp_file)
        assert File.exists?(tmp_file)

        # Check PNG magic bytes
        content = File.read!(tmp_file)
        assert <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>> = content
      after
        File.rm(tmp_file)
      end
    end

    test "exports to PGM file" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "2_ORIGINAL.dcm"))
      tmp_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(100_000)}.pgm")

      try do
        assert :ok = Image.to_file(dataset, tmp_file)
        assert File.exists?(tmp_file)

        content = File.read!(tmp_file)
        assert String.starts_with?(content, "P5\n")
      after
        File.rm(tmp_file)
      end
    end

    test "respects format option" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "2_ORIGINAL.dcm"))
      tmp_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(100_000)}.raw")

      try do
        assert :ok = Image.to_file(dataset, tmp_file, format: :pgm)
        assert File.exists?(tmp_file)

        content = File.read!(tmp_file)
        assert String.starts_with?(content, "P5\n")
      after
        File.rm(tmp_file)
      end
    end
  end

  describe "Image.encode/3" do
    test "encodes to PGM binary" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "2_ORIGINAL.dcm"))

      assert {:ok, binary} = Image.encode(dataset, :pgm)
      assert String.starts_with?(binary, "P5\n")
    end

    test "returns error for PNG binary encoding" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "2_ORIGINAL.dcm"))

      assert {:error, {:not_implemented, _}} = Image.encode(dataset, :png)
    end
  end

  describe "Dcmix.to_image/3" do
    test "exports to image file via main API" do
      {:ok, dataset} = Dcmix.read_file(Path.join(@fixtures_path, "2_ORIGINAL.dcm"))
      tmp_file = Path.join(System.tmp_dir!(), "test_api_#{:rand.uniform(100_000)}.png")

      try do
        assert :ok = Dcmix.to_image(dataset, tmp_file)
        assert File.exists?(tmp_file)
      after
        File.rm(tmp_file)
      end
    end
  end

  describe "Image.to_file/3 edge cases" do
    test "exports RGB image to PNG" do
      # Create 2x2 RGB image
      pixels = <<255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255>>
      dataset = create_rgb_dataset(2, 2, 8, "RGB", pixels)
      tmp_file = Path.join(System.tmp_dir!(), "test_rgb_#{:rand.uniform(100_000)}.png")

      try do
        assert :ok = Image.to_file(dataset, tmp_file)
        assert File.exists?(tmp_file)

        content = File.read!(tmp_file)
        assert <<0x89, "PNG", _::binary>> = content
      after
        File.rm(tmp_file)
      end
    end

    test "exports 16-bit grayscale to PNG (scales to 8-bit)" do
      # Create 2x2 16-bit grayscale
      pixels = <<0, 1, 0, 2, 0, 3, 0, 4>>
      dataset = create_grayscale_dataset(2, 2, 16, 0, "MONOCHROME2", pixels)
      tmp_file = Path.join(System.tmp_dir!(), "test_16bit_#{:rand.uniform(100_000)}.png")

      try do
        assert :ok = Image.to_file(dataset, tmp_file, window: :none)
        assert File.exists?(tmp_file)
      after
        File.rm(tmp_file)
      end
    end
  end

  describe "Decoder edge cases" do
    test "decodes 8-bit unsigned grayscale" do
      # Create 2x2 8-bit grayscale image
      pixels = <<100, 150, 200, 250>>
      dataset = create_grayscale_dataset(2, 2, 8, 0, "MONOCHROME2", pixels)

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.width == 2
      assert decoded.height == 2
      assert decoded.bit_depth == 8
    end

    test "decodes 8-bit signed grayscale" do
      # Create 2x2 8-bit signed grayscale (pixel_representation = 1)
      pixels = <<100, 150, 200, 250>>
      dataset = create_grayscale_dataset(2, 2, 8, 1, "MONOCHROME2", pixels)

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.bit_depth == 8
    end

    test "decodes 16-bit signed grayscale" do
      # Create 2x2 16-bit signed grayscale
      pixels = <<100, 0, 150, 0, 200, 0, 250, 0>>
      dataset = create_grayscale_dataset(2, 2, 16, 1, "MONOCHROME2", pixels)

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.bit_depth == 8
    end

    test "decodes RGB image" do
      # Create 2x2 RGB image (3 samples per pixel)
      pixels = <<255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255>>
      dataset = create_rgb_dataset(2, 2, 8, "RGB", pixels)

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.width == 2
      assert decoded.height == 2
      assert decoded.samples_per_pixel == 3
      assert decoded.photometric == :rgb
    end

    test "decodes 16-bit RGB image" do
      # Create 2x2 16-bit RGB image
      pixels = <<255, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 255, 0, 255, 0, 255, 0, 255, 0>>
      dataset = create_rgb_dataset(2, 2, 16, "RGB", pixels)

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.bit_depth == 8
      assert decoded.samples_per_pixel == 3
    end

    test "decodes planar RGB image" do
      # Create 2x2 planar RGB image (RRRRGGGGBBBB format)
      # 4 pixels: red, green, blue, white
      r_plane = <<255, 0, 0, 255>>
      g_plane = <<0, 255, 0, 255>>
      b_plane = <<0, 0, 255, 255>>
      pixels = r_plane <> g_plane <> b_plane
      dataset = create_rgb_dataset(2, 2, 8, "RGB", pixels, _planar = 1)

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.photometric == :rgb
    end

    test "decodes YBR_FULL image" do
      # Create 2x2 YBR_FULL image
      # Y=128, Cb=128, Cr=128 should be neutral gray
      pixels = <<128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128>>
      dataset = create_rgb_dataset(2, 2, 8, "YBR_FULL", pixels)

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.photometric == :rgb
    end

    test "decodes 16-bit YBR_FULL image" do
      # Create 2x2 16-bit YBR_FULL image
      pixels = :binary.copy(<<128, 0>>, 12)
      dataset = create_rgb_dataset(2, 2, 16, "YBR_FULL", pixels)

      assert {:ok, decoded} = Decoder.decode(dataset)
      assert decoded.photometric == :rgb
    end

    test "returns error for RGB with wrong samples_per_pixel" do
      pixels = <<100, 150, 200, 250>>
      dataset = create_grayscale_dataset(2, 2, 8, 0, "RGB", pixels)

      assert {:error, {:invalid_rgb, _}} = Decoder.decode(dataset)
    end

    test "returns error for YBR_FULL with wrong samples_per_pixel" do
      pixels = <<100, 150, 200, 250>>
      dataset = create_grayscale_dataset(2, 2, 8, 0, "YBR_FULL", pixels)

      assert {:error, {:invalid_ybr, _}} = Decoder.decode(dataset)
    end

    test "returns error for PALETTE COLOR" do
      pixels = <<100, 150, 200, 250>>
      dataset = create_grayscale_dataset(2, 2, 8, 0, "PALETTE COLOR", pixels)

      assert {:error, {:unsupported_photometric, _}} = Decoder.decode(dataset)
    end

    test "returns error for unknown photometric interpretation" do
      pixels = <<100, 150, 200, 250>>
      dataset = create_grayscale_dataset(2, 2, 8, 0, "UNKNOWN", pixels)

      assert {:error, {:unsupported_photometric, _}} = Decoder.decode(dataset)
    end
  end

  # Helper function to create a minimal DICOM dataset with pixel data
  defp create_minimal_image_dataset(width, height, bits_allocated) do
    pixel_size = div(bits_allocated, 8)
    pixels = :binary.copy(<<0>>, width * height * pixel_size)

    DataSet.new()
    |> DataSet.put_element({0x0028, 0x0010}, :US, height)
    |> DataSet.put_element({0x0028, 0x0011}, :US, width)
    |> DataSet.put_element({0x0028, 0x0002}, :US, 1)
    |> DataSet.put_element({0x0028, 0x0004}, :CS, "MONOCHROME2")
    |> DataSet.put_element({0x0028, 0x0100}, :US, bits_allocated)
    |> DataSet.put_element({0x0028, 0x0101}, :US, bits_allocated)
    |> DataSet.put_element({0x0028, 0x0102}, :US, bits_allocated - 1)
    |> DataSet.put_element({0x0028, 0x0103}, :US, 0)
    |> DataSet.put(DataElement.new({0x7FE0, 0x0010}, :OW, pixels))
  end

  defp create_grayscale_dataset(width, height, bits_allocated, pixel_rep, photometric, pixels) do
    vr = if bits_allocated == 8, do: :OB, else: :OW

    DataSet.new()
    |> DataSet.put_element({0x0028, 0x0010}, :US, height)
    |> DataSet.put_element({0x0028, 0x0011}, :US, width)
    |> DataSet.put_element({0x0028, 0x0002}, :US, 1)
    |> DataSet.put_element({0x0028, 0x0004}, :CS, photometric)
    |> DataSet.put_element({0x0028, 0x0100}, :US, bits_allocated)
    |> DataSet.put_element({0x0028, 0x0101}, :US, bits_allocated)
    |> DataSet.put_element({0x0028, 0x0102}, :US, bits_allocated - 1)
    |> DataSet.put_element({0x0028, 0x0103}, :US, pixel_rep)
    |> DataSet.put(DataElement.new({0x7FE0, 0x0010}, vr, pixels))
  end

  defp create_rgb_dataset(width, height, bits_allocated, photometric, pixels, planar \\ 0) do
    vr = if bits_allocated == 8, do: :OB, else: :OW

    DataSet.new()
    |> DataSet.put_element({0x0028, 0x0010}, :US, height)
    |> DataSet.put_element({0x0028, 0x0011}, :US, width)
    |> DataSet.put_element({0x0028, 0x0002}, :US, 3)
    |> DataSet.put_element({0x0028, 0x0004}, :CS, photometric)
    |> DataSet.put_element({0x0028, 0x0006}, :US, planar)
    |> DataSet.put_element({0x0028, 0x0100}, :US, bits_allocated)
    |> DataSet.put_element({0x0028, 0x0101}, :US, bits_allocated)
    |> DataSet.put_element({0x0028, 0x0102}, :US, bits_allocated - 1)
    |> DataSet.put_element({0x0028, 0x0103}, :US, 0)
    |> DataSet.put(DataElement.new({0x7FE0, 0x0010}, vr, pixels))
  end
end
