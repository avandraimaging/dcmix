defmodule Dcmix.Export.Image do
  @moduledoc """
  Exports DICOM pixel data to standard image formats.

  Supports PNG and PPM/PGM formats.
  Similar to dcmtk's `dcm2pnm` and dicom-rs's `dicom-toimage`.

  ## Usage

      # Export to PNG file
      {:ok, dataset} = Dcmix.read_file("image.dcm")
      :ok = Dcmix.Export.Image.to_file(dataset, "output.png")

      # With options
      :ok = Dcmix.Export.Image.to_file(dataset, "output.png",
        frame: 0,
        window: :auto
      )

      # Export to PPM/PGM
      :ok = Dcmix.Export.Image.to_file(dataset, "output.ppm")

  ## Supported Formats

  - **PNG** - Portable Network Graphics (8-bit grayscale or RGB)
  - **PPM** - Portable Pixmap (RGB color)
  - **PGM** - Portable Graymap (grayscale)

  ## Options

  - `:frame` - Frame number for multi-frame images (0-indexed, default: 0)
  - `:window` - Windowing for grayscale images:
    - `:auto` - Use VOI LUT from DICOM tags if available, else min/max (default)
    - `:min_max` - Window based on actual min/max pixel values
    - `:none` - No windowing (preserves raw values)
    - `{center, width}` - Explicit window center and width
  - `:format` - Output format (:png, :ppm, :pgm), auto-detected from file extension

  ## Limitations

  - Only supports uncompressed (native) pixel data
  - For compressed data (JPEG, JPEG2000, etc.), external decompression is required first
  """

  alias Dcmix.DataSet
  alias Dcmix.Export.Image.{Decoder, PPM}

  @type format :: :png | :ppm | :pgm

  @doc """
  Decodes pixel data from a DICOM dataset.

  Returns a decoded image structure that can be encoded to various formats.

  ## Examples

      {:ok, decoded} = Dcmix.Export.Image.decode(dataset)
      {:ok, decoded} = Dcmix.Export.Image.decode(dataset, frame: 0, window: :auto)
  """
  @spec decode(DataSet.t(), keyword()) :: {:ok, Decoder.decoded_image()} | {:error, term()}
  defdelegate decode(dataset, opts \\ []), to: Decoder

  @doc """
  Exports a DICOM dataset to an image file.

  The output format is inferred from the file extension (.png, .ppm, .pgm)
  or can be explicitly specified with the `:format` option.

  ## Examples

      :ok = Dcmix.Export.Image.to_file(dataset, "output.png")
      :ok = Dcmix.Export.Image.to_file(dataset, "output.png", frame: 0)
      :ok = Dcmix.Export.Image.to_file(dataset, "output.pgm", window: :min_max)
  """
  @spec to_file(DataSet.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_file(%DataSet{} = dataset, path, opts \\ []) do
    format = Keyword.get(opts, :format) || format_from_extension(path)

    with {:ok, decoded} <- decode(dataset, opts) do
      encode_to_file(decoded, path, format)
    end
  end

  @doc """
  Encodes a DICOM dataset to image binary data.

  ## Examples

      {:ok, png_binary} = Dcmix.Export.Image.encode(dataset, :png)
      {:ok, pgm_binary} = Dcmix.Export.Image.encode(dataset, :pgm)
  """
  @spec encode(DataSet.t(), format(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%DataSet{} = dataset, format, opts \\ []) do
    with {:ok, decoded} <- decode(dataset, opts) do
      encode_decoded(decoded, format)
    end
  end

  @doc """
  Exports all frames from a multi-frame DICOM dataset to separate image files.

  Similar to dcmtk's `dcm2pnm --all-frames`.

  The path must contain a format specifier for the frame number:
  - `%d` - frame number (0, 1, 2, ...)
  - `%04d` - zero-padded frame number (0000, 0001, 0002, ...)

  ## Options

  - `:frames` - List of specific frame indices to export (default: all frames)
  - `:window` - Windowing option (same as `to_file/3`)
  - `:format` - Output format (:png, :ppm, :pgm), auto-detected from extension

  ## Examples

      # Export all frames
      {:ok, paths} = Dcmix.Export.Image.to_files(dataset, "output/frame_%04d.png")

      # Export specific frames
      {:ok, paths} = Dcmix.Export.Image.to_files(dataset, "output/frame_%04d.png", frames: [0, 5, 10])

  ## Returns

      {:ok, [path1, path2, ...]} - List of created file paths
      {:error, reason} - If export fails
  """
  @spec to_files(DataSet.t(), Path.t(), keyword()) :: {:ok, [Path.t()]} | {:error, term()}
  def to_files(%DataSet{} = dataset, path_pattern, opts \\ []) do
    with {:ok, info} <- Decoder.get_pixel_info(dataset) do
      num_frames = info.number_of_frames
      frames_to_export = Keyword.get(opts, :frames) || Enum.to_list(0..(num_frames - 1))

      # Validate frame indices
      invalid_frames = Enum.filter(frames_to_export, fn f -> f < 0 or f >= num_frames end)

      if invalid_frames != [] do
        {:error,
         {:invalid_frames, "Frames #{inspect(invalid_frames)} out of range (0-#{num_frames - 1})"}}
      else
        export_frames(dataset, path_pattern, frames_to_export, opts)
      end
    end
  end

  defp export_frames(dataset, path_pattern, frames, opts) do
    results =
      Enum.map(frames, fn frame_idx ->
        path = format_path(path_pattern, frame_idx)
        frame_opts = Keyword.put(opts, :frame, frame_idx)

        case to_file(dataset, path, frame_opts) do
          :ok -> {:ok, path}
          {:error, reason} -> {:error, {frame_idx, reason}}
        end
      end)

    errors = Enum.filter(results, fn r -> match?({:error, _}, r) end)

    if errors == [] do
      {:ok, Enum.map(results, fn {:ok, path} -> path end)}
    else
      {:error, {:export_failed, errors}}
    end
  end

  defp format_path(pattern, frame_idx) do
    # Support printf-style format specifiers like %d, %04d, %4d
    Regex.replace(~r/%(\d*)d/, pattern, fn _match, width ->
      case width do
        "" -> Integer.to_string(frame_idx)
        w -> String.pad_leading(Integer.to_string(frame_idx), String.to_integer(w), "0")
      end
    end)
  end

  # Determine format from file extension
  defp format_from_extension(path) do
    case Path.extname(path) |> String.downcase() do
      ".png" -> :png
      ".ppm" -> :ppm
      ".pgm" -> :pgm
      _ -> :png
    end
  end

  # Encode decoded image to file
  defp encode_to_file(decoded, path, :png) do
    write_png_file(decoded, path)
  end

  defp encode_to_file(decoded, path, format) when format in [:ppm, :pgm] do
    PPM.to_file(decoded, path)
  end

  # Encode decoded image to binary
  defp encode_decoded(decoded, format) when format in [:ppm, :pgm] do
    PPM.encode(decoded)
  end

  defp encode_decoded(_decoded, :png) do
    {:error, {:not_implemented, "PNG binary encoding requires writing to file"}}
  end

  # Write PNG file using the png library (works with raw binary data)
  defp write_png_file(%{photometric: :grayscale} = decoded, path) do
    %{width: width, height: height, bit_depth: bit_depth, pixels: pixels} = decoded

    # Convert to 8-bit if necessary
    pixel_bytes =
      if bit_depth == 16 do
        scale_16_to_8(pixels)
      else
        pixels
      end

    {:ok, file} = File.open(path, [:write, :binary])

    try do
      config = %{size: {width, height}, mode: {:grayscale, 8}, file: file}
      png = :png.create(config)

      # Split pixels into rows and append each row
      rows = for <<row::binary-size(width) <- pixel_bytes>>, do: row
      :png.append(png, {:rows, rows})
      :png.close(png)
      :ok
    after
      File.close(file)
    end
  end

  defp write_png_file(%{photometric: :rgb} = decoded, path) do
    %{width: width, height: height, pixels: pixels} = decoded

    {:ok, file} = File.open(path, [:write, :binary])

    try do
      config = %{size: {width, height}, mode: {:rgb, 8}, file: file}
      png = :png.create(config)

      # Split pixels into rows (3 bytes per pixel)
      row_size = width * 3
      rows = for <<row::binary-size(row_size) <- pixels>>, do: row
      :png.append(png, {:rows, rows})
      :png.close(png)
      :ok
    after
      File.close(file)
    end
  end

  # Scale 16-bit grayscale to 8-bit
  defp scale_16_to_8(pixels) do
    for <<v::little-unsigned-integer-16 <- pixels>>, into: <<>> do
      <<div(v, 256)::unsigned-integer-8>>
    end
  end
end
