defmodule Dcmix.Export.Image.PPM do
  @moduledoc """
  Encoder for PPM (Portable Pixmap) and PGM (Portable Graymap) formats.

  These are simple image formats that require no external dependencies.
  Useful for debugging, integration with other tools, or when PNG is not needed.

  ## Formats

  - **PGM** (P5) - Binary grayscale format
  - **PPM** (P6) - Binary RGB color format

  Both formats support 8-bit and 16-bit samples.
  """

  alias Dcmix.Export.Image.Decoder

  @doc """
  Encodes a decoded image to PPM/PGM binary format.

  Returns PGM for grayscale images, PPM for RGB images.

  ## Examples

      {:ok, binary} = Dcmix.Export.Image.PPM.encode(decoded_image)
  """
  @spec encode(Decoder.decoded_image()) :: {:ok, binary()} | {:error, term()}
  def encode(%{photometric: :grayscale} = image), do: encode_pgm(image)
  def encode(%{photometric: :rgb} = image), do: encode_ppm(image)

  @doc """
  Writes a decoded image to a PPM/PGM file.

  ## Examples

      :ok = Dcmix.Export.Image.PPM.to_file(decoded_image, "output.pgm")
  """
  @spec to_file(Decoder.decoded_image(), Path.t()) :: :ok | {:error, term()}
  def to_file(image, path) do
    {:ok, binary} = encode(image)
    File.write(path, binary)
  end

  # Encode grayscale image to PGM (P5) format
  defp encode_pgm(%{width: width, height: height, bit_depth: bit_depth, pixels: pixels}) do
    max_val = if bit_depth == 16, do: 65_535, else: 255

    # PGM format: P5 magic, width height, max value, then binary data
    header = "P5\n#{width} #{height}\n#{max_val}\n"

    # For 16-bit PGM, pixels need to be big-endian
    pixel_data =
      if bit_depth == 16 do
        convert_to_big_endian_16(pixels)
      else
        pixels
      end

    {:ok, header <> pixel_data}
  end

  # Encode RGB image to PPM (P6) format
  defp encode_ppm(%{width: width, height: height, bit_depth: bit_depth, pixels: pixels}) do
    max_val = if bit_depth == 16, do: 65_535, else: 255

    # PPM format: P6 magic, width height, max value, then binary data
    header = "P6\n#{width} #{height}\n#{max_val}\n"

    # For 16-bit PPM, pixels need to be big-endian
    pixel_data =
      if bit_depth == 16 do
        convert_to_big_endian_16(pixels)
      else
        pixels
      end

    {:ok, header <> pixel_data}
  end

  # Convert 16-bit little-endian pixels to big-endian for PPM/PGM
  defp convert_to_big_endian_16(binary) do
    for <<v::little-unsigned-integer-16 <- binary>>, into: <<>> do
      <<v::big-unsigned-integer-16>>
    end
  end
end
