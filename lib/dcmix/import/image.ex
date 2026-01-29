defmodule Dcmix.Import.Image do
  @moduledoc """
  Imports images (PNG, JPEG) into DICOM format.

  Similar to dcmtk's `img2dcm` and dicom-rs's image import functionality.

  ## Usage

      # Create DICOM from image with template
      {:ok, template} = Dcmix.read_file("template.dcm")
      {:ok, dataset} = Dcmix.Import.Image.from_file("image.png", dataset_from: template)

      # Create DICOM from image with study/series from another DICOM
      {:ok, source} = Dcmix.read_file("source.dcm")
      {:ok, dataset} = Dcmix.Import.Image.from_file("image.png", series_from: source)

      # Create new DICOM with auto-generated attributes
      {:ok, dataset} = Dcmix.Import.Image.from_file("image.png")

  ## Options

  - `:dataset_from` - Template DataSet to use as base (like dcmtk's --dataset-from)
  - `:study_from` - DataSet to copy patient/study info from (like dcmtk's --study-from)
  - `:series_from` - DataSet to copy patient/study/series info from (like dcmtk's --series-from)
  - `:sop_class` - SOP Class to use (:secondary_capture, :vl_photo, default: :secondary_capture)
  - `:insert_type2` - Auto-insert missing Type 2 attributes (default: true)
  - `:invent_type1` - Auto-generate missing Type 1 values (default: true)

  ## Supported Input Formats

  - **PNG** - Portable Network Graphics (uncompressed pixel data extracted)
  - **JPEG** - JPEG images (stored as encapsulated data, like dcmtk's img2dcm)

  ## SOP Classes

  - `:secondary_capture` - Secondary Capture Image Storage (default)
  - `:vl_photo` - VL Photographic Image Storage
  """

  alias Dcmix.DataSet

  # SOP Class UIDs
  @secondary_capture_uid "1.2.840.10008.5.1.4.1.1.7"
  @vl_photo_uid "1.2.840.10008.5.1.4.1.1.77.1.4"

  # Patient module tags (copied by --study-from and --series-from)
  @patient_tags [
    # PatientName
    {0x0010, 0x0010},
    # PatientID
    {0x0010, 0x0020},
    # PatientBirthDate
    {0x0010, 0x0030},
    # PatientSex
    {0x0010, 0x0040}
  ]

  # Study module tags (copied by --study-from and --series-from)
  @study_tags [
    # StudyInstanceUID
    {0x0020, 0x000D},
    # StudyDate
    {0x0008, 0x0020},
    # StudyTime
    {0x0008, 0x0030},
    # ReferringPhysicianName
    {0x0008, 0x0090},
    # StudyID
    {0x0020, 0x0010},
    # AccessionNumber
    {0x0008, 0x0050}
  ]

  # Series module tags (copied by --series-from only)
  @series_tags [
    # SeriesInstanceUID
    {0x0020, 0x000E},
    # SeriesNumber
    {0x0020, 0x0011},
    # Modality
    {0x0008, 0x0060},
    # Manufacturer
    {0x0008, 0x0070}
  ]

  @doc """
  Creates a DICOM DataSet from an image file.

  ## Examples

      {:ok, dataset} = Dcmix.Import.Image.from_file("image.png")
      {:ok, dataset} = Dcmix.Import.Image.from_file("image.png", dataset_from: template)
  """
  @spec from_file(Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def from_file(path, opts \\ []) do
    with {:ok, image_data} <- read_image(path) do
      build_dataset(image_data, opts)
    end
  end

  @doc """
  Creates a DICOM DataSet from image binary data.

  The format must be specified via the `:format` option (:png or :jpeg).
  """
  @spec from_binary(binary(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def from_binary(data, opts \\ []) do
    format = Keyword.get(opts, :format, :png)

    with {:ok, image_data} <- decode_image(data, format) do
      build_dataset(image_data, opts)
    end
  end

  @doc """
  Creates a multi-frame DICOM DataSet from multiple image files.

  Similar to dcmtk's `img2dcm --new-sc` with multiple input files.

  Accepts either a list of file paths or a glob pattern.

  ## Options

  All options from `from_file/2` are supported, plus:

  - `:sort` - Sort files before combining (default: true)
    - `true` - Natural sort (file1.png, file2.png, file10.png)
    - `false` - Use order as provided
    - `:name` - Sort alphabetically by filename
    - `:mtime` - Sort by modification time

  ## Examples

      # From list of files
      {:ok, dataset} = Dcmix.Import.Image.from_files(["frame1.png", "frame2.png", "frame3.png"])

      # From glob pattern
      {:ok, dataset} = Dcmix.Import.Image.from_files("frames/*.png")

      # With template
      {:ok, template} = Dcmix.read_file("template.dcm")
      {:ok, dataset} = Dcmix.Import.Image.from_files("frames/*.png", series_from: template)

  ## Requirements

  All input images must have:
  - Same dimensions (width and height)
  - Same color type (grayscale or RGB)
  - Same bit depth
  """
  @spec from_files([Path.t()] | Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def from_files(paths_or_pattern, opts \\ [])

  def from_files(pattern, opts) when is_binary(pattern) do
    paths = Path.wildcard(pattern)

    if paths == [] do
      {:error, {:no_files_found, "No files matching pattern: #{pattern}"}}
    else
      from_files(paths, opts)
    end
  end

  def from_files([], _opts) do
    {:error, {:no_files, "At least one image file is required"}}
  end

  def from_files(paths, opts) when is_list(paths) do
    sorted_paths = sort_paths(paths, Keyword.get(opts, :sort, true))
    build_multiframe_dataset(sorted_paths, opts)
  end

  defp sort_paths(paths, false), do: paths
  defp sort_paths(paths, :name), do: Enum.sort(paths)
  defp sort_paths(paths, :mtime), do: Enum.sort_by(paths, &file_mtime/1)
  defp sort_paths(paths, true), do: Enum.sort_by(paths, &natural_sort_key/1)

  defp file_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> {{0, 0, 0}, {0, 0, 0}}
    end
  end

  # Natural sort: file1.png, file2.png, file10.png
  defp natural_sort_key(path) do
    Path.basename(path)
    |> String.split(~r/(\d+)/)
    |> Enum.map(&natural_sort_part/1)
  end

  defp natural_sort_part(part) do
    case Integer.parse(part) do
      {num, ""} -> {0, num}
      _ -> {1, part}
    end
  end

  defp build_multiframe_dataset(paths, opts) do
    # Read all images and validate they're compatible
    with {:ok, images} <- read_all_images(paths),
         :ok <- validate_compatible_images(images) do
      first_image = hd(images)
      combined_pixels = combine_pixel_data(images)
      num_frames = length(images)

      # Build multi-frame image data
      multiframe_data = %{
        width: first_image.width,
        height: first_image.height,
        photometric: first_image.photometric,
        samples_per_pixel: first_image.samples_per_pixel,
        bits_allocated: first_image.bits_allocated,
        bits_stored: first_image.bits_stored,
        high_bit: first_image.high_bit,
        pixel_data: combined_pixels,
        compressed: false,
        number_of_frames: num_frames
      }

      build_multiframe_dataset_from_data(multiframe_data, opts)
    end
  end

  defp read_all_images(paths) do
    results = Enum.map(paths, fn path -> {path, read_image(path)} end)
    errors = Enum.filter(results, fn {_, result} -> match?({:error, _}, result) end)

    if errors == [] do
      {:ok, Enum.map(results, fn {_, {:ok, img}} -> img end)}
    else
      failed = Enum.map(errors, fn {path, {:error, reason}} -> {path, reason} end)
      {:error, {:read_failed, failed}}
    end
  end

  defp validate_compatible_images([]), do: {:error, :no_images}
  defp validate_compatible_images([_single]), do: :ok

  defp validate_compatible_images([first | rest]) do
    incompatible =
      Enum.filter(rest, fn img ->
        img.width != first.width or
          img.height != first.height or
          img.samples_per_pixel != first.samples_per_pixel or
          img.bits_allocated != first.bits_allocated
      end)

    if incompatible == [] do
      :ok
    else
      {:error,
       {:incompatible_images,
        "All images must have same dimensions (#{first.width}x#{first.height}), " <>
          "samples per pixel (#{first.samples_per_pixel}), and bit depth (#{first.bits_allocated})"}}
    end
  end

  defp combine_pixel_data(images) do
    images
    |> Enum.map(fn img -> img.pixel_data end)
    |> IO.iodata_to_binary()
  end

  defp build_multiframe_dataset_from_data(image_data, opts) do
    dataset_from = Keyword.get(opts, :dataset_from)
    study_from = Keyword.get(opts, :study_from)
    series_from = Keyword.get(opts, :series_from)
    sop_class = Keyword.get(opts, :sop_class, :multiframe_secondary_capture)
    insert_type2 = Keyword.get(opts, :insert_type2, true)
    invent_type1 = Keyword.get(opts, :invent_type1, true)

    # Start with template or empty dataset
    base_dataset =
      case dataset_from do
        %DataSet{} = ds -> ds
        _ -> DataSet.new()
      end

    # Copy study/series info if specified
    dataset =
      base_dataset
      |> maybe_copy_study_info(study_from)
      |> maybe_copy_series_info(series_from)

    # Add image-specific attributes
    dataset =
      dataset
      |> add_multiframe_image_attributes(image_data)
      |> add_multiframe_sop_class(sop_class)
      |> maybe_insert_type2(insert_type2)
      |> maybe_invent_type1(invent_type1)

    {:ok, dataset}
  end

  defp add_multiframe_image_attributes(dataset, image_data) do
    %{
      width: width,
      height: height,
      photometric: photometric,
      samples_per_pixel: samples_per_pixel,
      bits_allocated: bits_allocated,
      bits_stored: bits_stored,
      high_bit: high_bit,
      pixel_data: pixel_data,
      number_of_frames: number_of_frames
    } = image_data

    photometric_str = photometric_to_string(photometric)
    pixel_vr = if bits_allocated > 8, do: :OW, else: :OB

    dataset
    # Rows
    |> DataSet.put_element({0x0028, 0x0010}, :US, height)
    # Columns
    |> DataSet.put_element({0x0028, 0x0011}, :US, width)
    # SamplesPerPixel
    |> DataSet.put_element({0x0028, 0x0002}, :US, samples_per_pixel)
    # PhotometricInterpretation
    |> DataSet.put_element({0x0028, 0x0004}, :CS, photometric_str)
    # NumberOfFrames
    |> DataSet.put_element({0x0028, 0x0008}, :IS, Integer.to_string(number_of_frames))
    # BitsAllocated
    |> DataSet.put_element({0x0028, 0x0100}, :US, bits_allocated)
    # BitsStored
    |> DataSet.put_element({0x0028, 0x0101}, :US, bits_stored)
    # HighBit
    |> DataSet.put_element({0x0028, 0x0102}, :US, high_bit)
    # PixelRepresentation (unsigned)
    |> DataSet.put_element({0x0028, 0x0103}, :US, 0)
    # PixelData
    |> DataSet.put_element({0x7FE0, 0x0010}, pixel_vr, pixel_data)
  end

  # Multi-frame Secondary Capture SOP Classes
  @multiframe_grayscale_byte_sc_uid "1.2.840.10008.5.1.4.1.1.7.2"
  @multiframe_grayscale_word_sc_uid "1.2.840.10008.5.1.4.1.1.7.3"
  @multiframe_true_color_sc_uid "1.2.840.10008.5.1.4.1.1.7.4"

  defp add_multiframe_sop_class(dataset, :multiframe_secondary_capture) do
    # Choose appropriate multi-frame SC class based on image properties
    samples = DataSet.get_value(dataset, {0x0028, 0x0002}) || 1
    bits = DataSet.get_value(dataset, {0x0028, 0x0100}) || 8

    sop_class_uid =
      cond do
        samples == 3 -> @multiframe_true_color_sc_uid
        bits > 8 -> @multiframe_grayscale_word_sc_uid
        true -> @multiframe_grayscale_byte_sc_uid
      end

    DataSet.put_element(dataset, {0x0008, 0x0016}, :UI, sop_class_uid)
  end

  defp add_multiframe_sop_class(dataset, :secondary_capture) do
    # Use single-frame SC class (deprecated for multi-frame but still supported)
    DataSet.put_element(dataset, {0x0008, 0x0016}, :UI, @secondary_capture_uid)
  end

  defp add_multiframe_sop_class(dataset, _),
    do: add_multiframe_sop_class(dataset, :multiframe_secondary_capture)

  defp read_image(path) do
    if File.exists?(path) do
      format = format_from_extension(path)

      case File.read(path) do
        {:ok, data} -> decode_image(data, format)
        {:error, reason} -> {:error, {:file_read_error, reason}}
      end
    else
      {:error, {:file_not_found, path}}
    end
  end

  defp format_from_extension(path) do
    case Path.extname(path) |> String.downcase() do
      ".png" -> :png
      ".jpg" -> :jpeg
      ".jpeg" -> :jpeg
      _ -> :png
    end
  end

  defp decode_image(data, :png) do
    decode_png(data)
  end

  defp decode_image(data, :jpeg) do
    # For JPEG, we store the compressed data directly (like dcmtk's img2dcm)
    # This avoids needing a JPEG decoder
    decode_jpeg_header(data)
  end

  defp decode_png(data) do
    # Parse PNG and decompress pixel data
    case parse_png(data) do
      {:ok, header, pixel_data} ->
        {photometric, samples_per_pixel} = png_color_type_to_dicom(header.color_type)
        bits_allocated = normalize_bit_depth(header.bit_depth)

        {:ok,
         %{
           width: header.width,
           height: header.height,
           photometric: photometric,
           samples_per_pixel: samples_per_pixel,
           bits_allocated: bits_allocated,
           bits_stored: bits_allocated,
           high_bit: bits_allocated - 1,
           pixel_data: pixel_data,
           compressed: false
         }}

      {:error, reason} ->
        {:error, {:png_decode_error, reason}}
    end
  end

  # PNG magic number and IHDR chunk parsing
  defp parse_png(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, rest::binary>>) do
    with {:ok, header, rest} <- parse_ihdr(rest),
         {:ok, pixel_data} <- decompress_png_data(rest, header) do
      {:ok, header, pixel_data}
    end
  end

  defp parse_png(_), do: {:error, :invalid_png_signature}

  defp parse_ihdr(<<length::32, "IHDR", ihdr_data::binary-size(length), _crc::32, rest::binary>>) do
    <<width::32, height::32, bit_depth::8, color_type::8, _compression::8, _filter::8,
      _interlace::8>> = ihdr_data

    header = %{
      width: width,
      height: height,
      bit_depth: bit_depth,
      color_type: color_type
    }

    {:ok, header, rest}
  end

  defp parse_ihdr(_), do: {:error, :invalid_ihdr}

  defp decompress_png_data(data, header) do
    # Collect all IDAT chunks
    idat_data = collect_idat_chunks(data, <<>>)

    # Decompress using zlib
    try do
      decompressed = :zlib.uncompress(idat_data)

      # Remove PNG filter bytes (first byte of each row)
      pixel_data = remove_filter_bytes(decompressed, header)

      {:ok, pixel_data}
    rescue
      _ -> {:error, :decompression_failed}
    end
  end

  defp collect_idat_chunks(
         <<length::32, "IDAT", chunk_data::binary-size(length), _crc::32, rest::binary>>,
         acc
       ) do
    collect_idat_chunks(rest, <<acc::binary, chunk_data::binary>>)
  end

  defp collect_idat_chunks(<<_length::32, "IEND", _rest::binary>>, acc) do
    acc
  end

  defp collect_idat_chunks(
         <<length::32, _type::binary-size(4), _chunk_data::binary-size(length), _crc::32,
           rest::binary>>,
         acc
       ) do
    # Skip non-IDAT chunks
    collect_idat_chunks(rest, acc)
  end

  defp collect_idat_chunks(<<>>, acc), do: acc
  defp collect_idat_chunks(_, acc), do: acc

  defp remove_filter_bytes(data, header) do
    bytes_per_pixel = bytes_per_pixel(header.color_type, header.bit_depth)
    row_bytes = header.width * bytes_per_pixel
    # +1 for filter byte
    scanline_bytes = row_bytes + 1

    # Process each row, removing filter byte and applying filter if needed
    process_rows(data, scanline_bytes, row_bytes, <<>>)
  end

  defp process_rows(<<>>, _scanline_bytes, _row_bytes, acc), do: acc

  defp process_rows(data, scanline_bytes, row_bytes, acc)
       when byte_size(data) >= scanline_bytes do
    <<_filter::8, row_data::binary-size(row_bytes), rest::binary>> = data
    # Note: We're ignoring the filter byte here. Full implementation would apply the filter.
    # For filter type 0 (None), this is correct. Other filters would need proper handling.
    process_rows(rest, scanline_bytes, row_bytes, <<acc::binary, row_data::binary>>)
  end

  defp process_rows(_, _scanline_bytes, _row_bytes, acc), do: acc

  # Grayscale
  defp bytes_per_pixel(0, bit_depth), do: max(1, div(bit_depth, 8))
  # RGB
  defp bytes_per_pixel(2, bit_depth), do: 3 * max(1, div(bit_depth, 8))
  # Indexed
  defp bytes_per_pixel(3, _bit_depth), do: 1
  # Grayscale + Alpha
  defp bytes_per_pixel(4, bit_depth), do: 2 * max(1, div(bit_depth, 8))
  # RGBA
  defp bytes_per_pixel(6, bit_depth), do: 4 * max(1, div(bit_depth, 8))
  defp bytes_per_pixel(_, _), do: 1

  # Grayscale
  defp png_color_type_to_dicom(0), do: {:monochrome2, 1}
  # RGB
  defp png_color_type_to_dicom(2), do: {:rgb, 3}
  # Indexed (treat as grayscale)
  defp png_color_type_to_dicom(3), do: {:monochrome2, 1}
  # Grayscale + Alpha (drop alpha)
  defp png_color_type_to_dicom(4), do: {:monochrome2, 1}
  # RGBA (drop alpha)
  defp png_color_type_to_dicom(6), do: {:rgb, 3}
  defp png_color_type_to_dicom(_), do: {:monochrome2, 1}

  defp normalize_bit_depth(bit_depth) when bit_depth <= 8, do: 8
  defp normalize_bit_depth(bit_depth) when bit_depth <= 16, do: 16
  defp normalize_bit_depth(_), do: 8

  defp decode_jpeg_header(data) do
    # Parse JPEG header to get dimensions
    # JPEG SOI marker: 0xFFD8
    # SOF0 marker: 0xFFC0 (baseline), SOF2: 0xFFC2 (progressive)
    case parse_jpeg_dimensions(data) do
      {:ok, {width, height, components}} ->
        photometric = if components == 1, do: :monochrome2, else: :rgb

        {:ok,
         %{
           width: width,
           height: height,
           photometric: photometric,
           samples_per_pixel: components,
           bits_allocated: 8,
           bits_stored: 8,
           high_bit: 7,
           pixel_data: data,
           compressed: true,
           # JPEG Baseline
           transfer_syntax: "1.2.840.10008.1.2.4.50"
         }}

      :error ->
        {:error, :invalid_jpeg}
    end
  end

  defp parse_jpeg_dimensions(<<0xFF, 0xD8, rest::binary>>) do
    find_sof_marker(rest)
  end

  defp parse_jpeg_dimensions(_), do: :error

  defp find_sof_marker(<<0xFF, marker, _length::16, rest::binary>>)
       when marker in [0xC0, 0xC1, 0xC2, 0xC3] do
    # SOF marker found - extract dimensions
    # Format: precision (1), height (2), width (2), components (1)
    <<_precision::8, height::16, width::16, components::8, _::binary>> = rest
    {:ok, {width, height, components}}
  end

  defp find_sof_marker(<<0xFF, _marker, length::16, rest::binary>>) do
    # Skip this marker and continue
    skip_length = length - 2

    case rest do
      <<_skip::binary-size(skip_length), remaining::binary>> ->
        find_sof_marker(remaining)

      _ ->
        :error
    end
  end

  defp find_sof_marker(<<0xFF, rest::binary>>) do
    find_sof_marker(rest)
  end

  defp find_sof_marker(<<_::8, rest::binary>>) do
    find_sof_marker(rest)
  end

  defp find_sof_marker(<<>>), do: :error

  defp build_dataset(image_data, opts) do
    dataset_from = Keyword.get(opts, :dataset_from)
    study_from = Keyword.get(opts, :study_from)
    series_from = Keyword.get(opts, :series_from)
    sop_class = Keyword.get(opts, :sop_class, :secondary_capture)
    insert_type2 = Keyword.get(opts, :insert_type2, true)
    invent_type1 = Keyword.get(opts, :invent_type1, true)

    # Start with template or empty dataset
    base_dataset =
      case dataset_from do
        %DataSet{} = ds -> ds
        _ -> DataSet.new()
      end

    # Copy study/series info if specified
    dataset =
      base_dataset
      |> maybe_copy_study_info(study_from)
      |> maybe_copy_series_info(series_from)

    # Add image-specific attributes
    dataset =
      dataset
      |> add_image_attributes(image_data)
      |> add_sop_class(sop_class)
      |> maybe_insert_type2(insert_type2)
      |> maybe_invent_type1(invent_type1)

    {:ok, dataset}
  end

  defp maybe_copy_study_info(dataset, nil), do: dataset

  defp maybe_copy_study_info(dataset, source) do
    tags = @patient_tags ++ @study_tags
    copy_tags(dataset, source, tags)
  end

  defp maybe_copy_series_info(dataset, nil), do: dataset

  defp maybe_copy_series_info(dataset, source) do
    tags = @patient_tags ++ @study_tags ++ @series_tags
    copy_tags(dataset, source, tags)
  end

  defp copy_tags(dataset, source, tags) do
    Enum.reduce(tags, dataset, fn tag, acc ->
      case DataSet.get(source, tag) do
        nil -> acc
        element -> DataSet.put(acc, element)
      end
    end)
  end

  defp add_image_attributes(dataset, image_data) do
    %{
      width: width,
      height: height,
      photometric: photometric,
      samples_per_pixel: samples_per_pixel,
      bits_allocated: bits_allocated,
      bits_stored: bits_stored,
      high_bit: high_bit,
      pixel_data: pixel_data
    } = image_data

    photometric_str = photometric_to_string(photometric)
    pixel_vr = if bits_allocated > 8, do: :OW, else: :OB

    dataset
    # Rows
    |> DataSet.put_element({0x0028, 0x0010}, :US, height)
    # Columns
    |> DataSet.put_element({0x0028, 0x0011}, :US, width)
    # SamplesPerPixel
    |> DataSet.put_element({0x0028, 0x0002}, :US, samples_per_pixel)
    # PhotometricInterpretation
    |> DataSet.put_element({0x0028, 0x0004}, :CS, photometric_str)
    # BitsAllocated
    |> DataSet.put_element({0x0028, 0x0100}, :US, bits_allocated)
    # BitsStored
    |> DataSet.put_element({0x0028, 0x0101}, :US, bits_stored)
    # HighBit
    |> DataSet.put_element({0x0028, 0x0102}, :US, high_bit)
    # PixelRepresentation (unsigned)
    |> DataSet.put_element({0x0028, 0x0103}, :US, 0)
    # PixelData
    |> DataSet.put_element({0x7FE0, 0x0010}, pixel_vr, pixel_data)
  end

  defp photometric_to_string(:monochrome1), do: "MONOCHROME1"
  defp photometric_to_string(:monochrome2), do: "MONOCHROME2"
  defp photometric_to_string(:rgb), do: "RGB"
  defp photometric_to_string(_), do: "MONOCHROME2"

  defp add_sop_class(dataset, :secondary_capture) do
    DataSet.put_element(dataset, {0x0008, 0x0016}, :UI, @secondary_capture_uid)
  end

  defp add_sop_class(dataset, :vl_photo) do
    DataSet.put_element(dataset, {0x0008, 0x0016}, :UI, @vl_photo_uid)
  end

  defp add_sop_class(dataset, _), do: add_sop_class(dataset, :secondary_capture)

  defp maybe_insert_type2(dataset, false), do: dataset

  defp maybe_insert_type2(dataset, true) do
    # Type 2 attributes - required to be present, can be empty
    type2_defaults = [
      # StudyDate
      {{0x0008, 0x0020}, :DA, ""},
      # StudyTime
      {{0x0008, 0x0030}, :TM, ""},
      # AccessionNumber
      {{0x0008, 0x0050}, :SH, ""},
      # ReferringPhysicianName
      {{0x0008, 0x0090}, :PN, ""},
      # PatientName
      {{0x0010, 0x0010}, :PN, ""},
      # PatientID
      {{0x0010, 0x0020}, :LO, ""},
      # PatientBirthDate
      {{0x0010, 0x0030}, :DA, ""},
      # PatientSex
      {{0x0010, 0x0040}, :CS, ""},
      # StudyID
      {{0x0020, 0x0010}, :SH, ""},
      # SeriesNumber
      {{0x0020, 0x0011}, :IS, ""}
    ]

    Enum.reduce(type2_defaults, dataset, fn {tag, vr, default}, acc ->
      if DataSet.has_tag?(acc, tag) do
        acc
      else
        DataSet.put_element(acc, tag, vr, default)
      end
    end)
  end

  defp maybe_invent_type1(dataset, false), do: dataset

  defp maybe_invent_type1(dataset, true) do
    # Type 1 attributes - required with values
    # Generate UIDs and other required values
    dataset
    |> ensure_sop_instance_uid()
    |> ensure_study_instance_uid()
    |> ensure_series_instance_uid()
    |> ensure_modality()
    |> ensure_instance_number()
  end

  defp ensure_sop_instance_uid(dataset) do
    if DataSet.has_tag?(dataset, {0x0008, 0x0018}) do
      dataset
    else
      DataSet.put_element(dataset, {0x0008, 0x0018}, :UI, generate_uid())
    end
  end

  defp ensure_study_instance_uid(dataset) do
    if DataSet.has_tag?(dataset, {0x0020, 0x000D}) do
      dataset
    else
      DataSet.put_element(dataset, {0x0020, 0x000D}, :UI, generate_uid())
    end
  end

  defp ensure_series_instance_uid(dataset) do
    if DataSet.has_tag?(dataset, {0x0020, 0x000E}) do
      dataset
    else
      DataSet.put_element(dataset, {0x0020, 0x000E}, :UI, generate_uid())
    end
  end

  defp ensure_modality(dataset) do
    if DataSet.has_tag?(dataset, {0x0008, 0x0060}) do
      dataset
    else
      # Other
      DataSet.put_element(dataset, {0x0008, 0x0060}, :CS, "OT")
    end
  end

  defp ensure_instance_number(dataset) do
    if DataSet.has_tag?(dataset, {0x0020, 0x0013}) do
      dataset
    else
      DataSet.put_element(dataset, {0x0020, 0x0013}, :IS, "1")
    end
  end

  defp generate_uid do
    # Generate a unique UID using timestamp and random component
    # Format: 2.25.{UUID as decimal}
    uuid_bytes = :crypto.strong_rand_bytes(16)
    uuid_int = :binary.decode_unsigned(uuid_bytes)
    "2.25.#{uuid_int}"
  end
end
