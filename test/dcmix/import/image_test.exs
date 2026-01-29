defmodule Dcmix.Import.ImageTest do
  use ExUnit.Case, async: true

  alias Dcmix.Import.Image
  alias Dcmix.DataSet

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "nema_mr_brain_512x512.dcm")

  defp create_minimal_png do
    # PNG signature
    signature = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>

    # IHDR chunk: 2x2, 8-bit, RGB (color type 2)
    ihdr_data = <<0, 0, 0, 2, 0, 0, 0, 2, 8, 2, 0, 0, 0>>
    ihdr_crc = :erlang.crc32(<<"IHDR", ihdr_data::binary>>)
    ihdr = <<13::32, "IHDR", ihdr_data::binary, ihdr_crc::32>>

    # IDAT chunk: compressed pixel data
    # Raw data: 2 rows, each with filter byte (0) + 2 RGB pixels (6 bytes)
    raw_data = <<0, 255, 0, 0, 0, 255, 0, 0, 0, 0, 255, 255, 255, 255>>
    compressed = :zlib.compress(raw_data)
    idat_crc = :erlang.crc32(<<"IDAT", compressed::binary>>)
    idat = <<byte_size(compressed)::32, "IDAT", compressed::binary, idat_crc::32>>

    # IEND chunk
    iend_crc = :erlang.crc32("IEND")
    iend = <<0::32, "IEND", iend_crc::32>>

    signature <> ihdr <> idat <> iend
  end

  defp create_minimal_jpeg do
    # Minimal JPEG structure for testing header parsing
    # SOI marker
    soi = <<0xFF, 0xD8>>

    # APP0 marker (JFIF)
    app0 = <<0xFF, 0xE0, 0, 16, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0>>

    # DQT (quantization table)
    dqt = <<0xFF, 0xDB, 0, 67, 0>> <> :binary.copy(<<16>>, 64)

    # SOF0 marker (baseline DCT): 8-bit precision, 2x2, 3 components
    sof0 = <<0xFF, 0xC0, 0, 17, 8, 0, 2, 0, 2, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1>>

    # DHT (Huffman table) - minimal
    dht = <<0xFF, 0xC4, 0, 31, 0>> <> :binary.copy(<<0>>, 16) <> <<0>>

    # SOS marker
    sos = <<0xFF, 0xDA, 0, 12, 3, 1, 0, 2, 0x11, 3, 0x11, 0, 63, 0>>

    # Minimal scan data + EOI
    scan_data = <<0xFF, 0xD9>>

    soi <> app0 <> dqt <> sof0 <> dht <> sos <> scan_data
  end

  defp create_grayscale_png do
    # PNG signature
    signature = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>

    # IHDR chunk: 2x2, 8-bit, grayscale (color type 0)
    ihdr_data = <<0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 0>>
    ihdr_crc = :erlang.crc32(<<"IHDR", ihdr_data::binary>>)
    ihdr = <<13::32, "IHDR", ihdr_data::binary, ihdr_crc::32>>

    # IDAT chunk: 2 rows, each with filter byte + 2 grayscale pixels
    raw_data = <<0, 255, 128, 0, 64, 192>>
    compressed = :zlib.compress(raw_data)
    idat_crc = :erlang.crc32(<<"IDAT", compressed::binary>>)
    idat = <<byte_size(compressed)::32, "IDAT", compressed::binary, idat_crc::32>>

    # IEND chunk
    iend_crc = :erlang.crc32("IEND")
    iend = <<0::32, "IEND", iend_crc::32>>

    signature <> ihdr <> idat <> iend
  end

  describe "from_binary/2 with PNG" do
    test "decodes minimal PNG and creates dataset" do
      png = create_minimal_png()
      assert {:ok, dataset} = Image.from_binary(png, format: :png)

      # Check image dimensions
      # Rows
      assert DataSet.get_value(dataset, {0x0028, 0x0010}) == 2
      # Columns
      assert DataSet.get_value(dataset, {0x0028, 0x0011}) == 2

      # Check photometric interpretation for RGB
      assert DataSet.get_string(dataset, {0x0028, 0x0004}) == "RGB"

      # Check samples per pixel
      assert DataSet.get_value(dataset, {0x0028, 0x0002}) == 3

      # Check bits allocated
      assert DataSet.get_value(dataset, {0x0028, 0x0100}) == 8

      # Check pixel data exists
      assert DataSet.get(dataset, {0x7FE0, 0x0010}) != nil
    end

    test "creates secondary capture SOP class by default" do
      png = create_minimal_png()
      assert {:ok, dataset} = Image.from_binary(png, format: :png)
      assert DataSet.get_string(dataset, {0x0008, 0x0016}) == "1.2.840.10008.5.1.4.1.1.7"
    end

    test "creates VL photo SOP class when specified" do
      png = create_minimal_png()
      assert {:ok, dataset} = Image.from_binary(png, format: :png, sop_class: :vl_photo)
      assert DataSet.get_string(dataset, {0x0008, 0x0016}) == "1.2.840.10008.5.1.4.1.1.77.1.4"
    end

    test "inserts Type 2 attributes by default" do
      png = create_minimal_png()
      assert {:ok, dataset} = Image.from_binary(png, format: :png)

      # Type 2 attributes should be present (can be empty)
      # PatientName
      assert DataSet.has_tag?(dataset, {0x0010, 0x0010})
      # PatientID
      assert DataSet.has_tag?(dataset, {0x0010, 0x0020})
      # StudyDate
      assert DataSet.has_tag?(dataset, {0x0008, 0x0020})
    end

    test "invents Type 1 attributes by default" do
      png = create_minimal_png()
      assert {:ok, dataset} = Image.from_binary(png, format: :png)

      # Type 1 attributes should have values
      # SOPInstanceUID
      assert DataSet.get_string(dataset, {0x0008, 0x0018}) != nil
      # StudyInstanceUID
      assert DataSet.get_string(dataset, {0x0020, 0x000D}) != nil
      # SeriesInstanceUID
      assert DataSet.get_string(dataset, {0x0020, 0x000E}) != nil
      # Modality
      assert DataSet.get_string(dataset, {0x0008, 0x0060}) == "OT"
    end

    test "skips Type 2 attributes when insert_type2: false" do
      png = create_minimal_png()
      assert {:ok, dataset} = Image.from_binary(png, format: :png, insert_type2: false)

      # PatientName should not be present if not inserted
      refute DataSet.has_tag?(dataset, {0x0010, 0x0010})
    end

    test "skips Type 1 generation when invent_type1: false" do
      png = create_minimal_png()
      assert {:ok, dataset} = Image.from_binary(png, format: :png, invent_type1: false)

      # SOPInstanceUID should not be auto-generated
      refute DataSet.has_tag?(dataset, {0x0008, 0x0018})
    end
  end

  describe "from_binary/2 with JPEG" do
    test "decodes JPEG and creates dataset with compressed pixel data" do
      jpeg = create_minimal_jpeg()
      assert {:ok, dataset} = Image.from_binary(jpeg, format: :jpeg)

      # Check image dimensions
      # Rows
      assert DataSet.get_value(dataset, {0x0028, 0x0010}) == 2
      # Columns
      assert DataSet.get_value(dataset, {0x0028, 0x0011}) == 2

      # JPEG should have RGB photometric (3 components)
      assert DataSet.get_string(dataset, {0x0028, 0x0004}) == "RGB"
      assert DataSet.get_value(dataset, {0x0028, 0x0002}) == 3
    end
  end

  describe "from_file/2" do
    setup do
      tmp_dir = System.tmp_dir!()
      png_path = Path.join(tmp_dir, "test_#{:rand.uniform(100_000)}.png")
      jpeg_path = Path.join(tmp_dir, "test_#{:rand.uniform(100_000)}.jpg")

      File.write!(png_path, create_minimal_png())
      File.write!(jpeg_path, create_minimal_jpeg())

      on_exit(fn ->
        File.rm(png_path)
        File.rm(jpeg_path)
      end)

      {:ok, png_path: png_path, jpeg_path: jpeg_path}
    end

    test "reads PNG file and creates dataset", %{png_path: png_path} do
      assert {:ok, dataset} = Image.from_file(png_path)
      assert DataSet.get_value(dataset, {0x0028, 0x0010}) == 2
      assert DataSet.get_value(dataset, {0x0028, 0x0011}) == 2
    end

    test "reads JPEG file and creates dataset", %{jpeg_path: jpeg_path} do
      assert {:ok, dataset} = Image.from_file(jpeg_path)
      assert DataSet.get_value(dataset, {0x0028, 0x0010}) == 2
      assert DataSet.get_value(dataset, {0x0028, 0x0011}) == 2
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_not_found, _}} = Image.from_file("nonexistent.png")
    end
  end

  describe "from_file/2 with dataset_from option" do
    setup do
      tmp_dir = System.tmp_dir!()
      png_path = Path.join(tmp_dir, "test_#{:rand.uniform(100_000)}.png")
      File.write!(png_path, create_minimal_png())

      on_exit(fn -> File.rm(png_path) end)

      {:ok, png_path: png_path}
    end

    test "uses template dataset as base", %{png_path: png_path} do
      template =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Template^Patient")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "TEMPLATE123")

      assert {:ok, dataset} = Image.from_file(png_path, dataset_from: template)

      # Template values should be preserved
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "Template^Patient"
      assert DataSet.get_string(dataset, {0x0010, 0x0020}) == "TEMPLATE123"

      # Image data should still be added
      assert DataSet.get_value(dataset, {0x0028, 0x0010}) == 2
    end
  end

  describe "from_file/2 with study_from option" do
    setup do
      tmp_dir = System.tmp_dir!()
      png_path = Path.join(tmp_dir, "test_#{:rand.uniform(100_000)}.png")
      File.write!(png_path, create_minimal_png())

      on_exit(fn -> File.rm(png_path) end)

      {:ok, png_path: png_path}
    end

    test "copies patient and study info from source DICOM", %{png_path: png_path} do
      {:ok, source} = Dcmix.read_file(@valid_dcm)

      assert {:ok, dataset} = Image.from_file(png_path, study_from: source)

      # Patient info should be copied
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) ==
               DataSet.get_string(source, {0x0010, 0x0010})

      # Study info should be copied
      assert DataSet.get_string(dataset, {0x0020, 0x000D}) ==
               DataSet.get_string(source, {0x0020, 0x000D})

      # Series should NOT be copied (new series)
      # Series UID should be auto-generated and different
      assert DataSet.get_string(dataset, {0x0020, 0x000E}) !=
               DataSet.get_string(source, {0x0020, 0x000E})
    end
  end

  describe "from_file/2 with series_from option" do
    setup do
      tmp_dir = System.tmp_dir!()
      png_path = Path.join(tmp_dir, "test_#{:rand.uniform(100_000)}.png")
      File.write!(png_path, create_minimal_png())

      on_exit(fn -> File.rm(png_path) end)

      {:ok, png_path: png_path}
    end

    test "copies patient, study, and series info from source DICOM", %{png_path: png_path} do
      {:ok, source} = Dcmix.read_file(@valid_dcm)

      assert {:ok, dataset} = Image.from_file(png_path, series_from: source)

      # Patient info should be copied
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) ==
               DataSet.get_string(source, {0x0010, 0x0010})

      # Study info should be copied
      assert DataSet.get_string(dataset, {0x0020, 0x000D}) ==
               DataSet.get_string(source, {0x0020, 0x000D})

      # Series info should also be copied
      assert DataSet.get_string(dataset, {0x0020, 0x000E}) ==
               DataSet.get_string(source, {0x0020, 0x000E})
    end
  end

  describe "PNG parsing edge cases" do
    test "returns error for invalid PNG signature" do
      invalid_png = <<0x00, 0x00, 0x00, 0x00>>

      assert {:error, {:png_decode_error, :invalid_png_signature}} =
               Image.from_binary(invalid_png, format: :png)
    end

    test "returns error for truncated PNG" do
      truncated = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>
      assert {:error, {:png_decode_error, _}} = Image.from_binary(truncated, format: :png)
    end
  end

  describe "JPEG parsing edge cases" do
    test "returns error for invalid JPEG" do
      invalid_jpeg = <<0x00, 0x00, 0x00, 0x00>>
      assert {:error, :invalid_jpeg} = Image.from_binary(invalid_jpeg, format: :jpeg)
    end
  end

  describe "grayscale PNG" do
    test "handles grayscale PNG (color type 0)" do
      grayscale_png = create_grayscale_png()

      assert {:ok, dataset} = Image.from_binary(grayscale_png, format: :png)

      assert DataSet.get_string(dataset, {0x0028, 0x0004}) == "MONOCHROME2"
      assert DataSet.get_value(dataset, {0x0028, 0x0002}) == 1
    end
  end

  describe "generated UIDs" do
    test "generates unique UIDs each time" do
      png = create_minimal_png()
      {:ok, dataset1} = Image.from_binary(png, format: :png)
      {:ok, dataset2} = Image.from_binary(png, format: :png)

      # SOPInstanceUIDs should be different
      assert DataSet.get_string(dataset1, {0x0008, 0x0018}) !=
               DataSet.get_string(dataset2, {0x0008, 0x0018})
    end

    test "generated UIDs have correct format (2.25.xxx)" do
      png = create_minimal_png()
      {:ok, dataset} = Image.from_binary(png, format: :png)

      sop_uid = DataSet.get_string(dataset, {0x0008, 0x0018})
      assert String.starts_with?(sop_uid, "2.25.")
    end
  end
end
