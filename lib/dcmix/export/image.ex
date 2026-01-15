defmodule Dcmix.Export.Image do
  @moduledoc """
  Exports DICOM pixel data to standard image formats.

  Supports PNG (via ExPng library) and PPM/PGM formats.
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
    {:ok, image} = encode_to_png(decoded)

    case ExPng.Image.to_file(image, path) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp encode_to_file(decoded, path, format) when format in [:ppm, :pgm] do
    PPM.to_file(decoded, path)
  end

  # Encode decoded image to binary
  defp encode_decoded(decoded, format) when format in [:ppm, :pgm] do
    PPM.encode(decoded)
  end

  defp encode_decoded(decoded, :png) do
    # PNG binary encoding would require temporary file or expanding ExPng
    # For now, return error as ExPng doesn't expose binary encoding
    {:ok, _image} = encode_to_png(decoded)
    {:error, {:not_implemented, "PNG binary encoding requires writing to file"}}
  end

  # Convert decoded image to ExPng.Image
  defp encode_to_png(%{photometric: :grayscale} = decoded) do
    %{width: width, height: height, bit_depth: bit_depth, pixels: pixels} = decoded

    # Convert to 8-bit if necessary (ExPng only supports 8-bit)
    pixel_bytes =
      if bit_depth == 16 do
        scale_16_to_8(pixels)
      else
        pixels
      end

    # Convert binary to list of rows of Color.t()
    rows = build_grayscale_rows(pixel_bytes, width, height)

    {:ok, ExPng.Image.new(rows)}
  end

  defp encode_to_png(%{photometric: :rgb} = decoded) do
    %{width: width, height: height, bit_depth: _bit_depth, pixels: pixels} = decoded

    # Convert binary to list of rows of Color.t()
    rows = build_rgb_rows(pixels, width, height)

    {:ok, ExPng.Image.new(rows)}
  end

  # Build 2D list of grayscale pixels for ExPng
  defp build_grayscale_rows(pixels, width, height) do
    for row_idx <- 0..(height - 1) do
      row_offset = row_idx * width

      for col_idx <- 0..(width - 1) do
        <<gray>> = binary_part(pixels, row_offset + col_idx, 1)
        ExPng.Color.grayscale(gray)
      end
    end
  end

  # Build 2D list of RGB pixels for ExPng
  defp build_rgb_rows(pixels, width, height) do
    # Each pixel is 3 bytes (RGB)
    for row_idx <- 0..(height - 1) do
      row_offset = row_idx * width * 3

      for col_idx <- 0..(width - 1) do
        pixel_offset = row_offset + col_idx * 3
        <<r, g, b>> = binary_part(pixels, pixel_offset, 3)
        ExPng.Color.rgb(r, g, b)
      end
    end
  end

  # Scale 16-bit grayscale to 8-bit
  defp scale_16_to_8(pixels) do
    for <<v::little-unsigned-integer-16 <- pixels>>, into: <<>> do
      <<div(v, 256)::unsigned-integer-8>>
    end
  end
end
