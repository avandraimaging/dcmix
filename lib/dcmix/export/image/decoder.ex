defmodule Dcmix.Export.Image.Decoder do
  @moduledoc """
  Decodes DICOM pixel data into a format suitable for image export.

  Handles various photometric interpretations, bit depths, and pixel
  representations to produce normalized pixel data for image encoders.
  """

  import Bitwise

  alias Dcmix.{DataSet, PixelData}

  @type pixel_info :: %{
          rows: pos_integer(),
          columns: pos_integer(),
          samples_per_pixel: pos_integer(),
          bits_allocated: pos_integer(),
          bits_stored: pos_integer(),
          high_bit: pos_integer(),
          pixel_representation: 0 | 1,
          photometric_interpretation: String.t(),
          number_of_frames: pos_integer(),
          planar_configuration: 0 | 1 | nil
        }

  @type decoded_image :: %{
          width: pos_integer(),
          height: pos_integer(),
          samples_per_pixel: pos_integer(),
          bit_depth: 8 | 16,
          pixels: binary(),
          photometric: :grayscale | :rgb
        }

  @type window_spec :: :auto | :min_max | :none | {number(), number()}

  @doc """
  Decodes pixel data from a DICOM dataset.

  Returns a decoded image structure with normalized pixel data ready
  for encoding to standard image formats.

  ## Options

  - `:frame` - Frame number for multi-frame images (0-indexed, default: 0)
  - `:window` - Windowing for grayscale images:
    - `:auto` - Use VOI LUT from DICOM tags if available, else min/max
    - `:min_max` - Window based on actual min/max pixel values
    - `:none` - No windowing (may require 16-bit output)
    - `{center, width}` - Explicit window center and width
  - `:output_bits` - Force output bit depth (8 or 16, default: 8 for windowed, 16 for none)

  ## Examples

      {:ok, decoded} = Dcmix.Export.Image.Decoder.decode(dataset)
      {:ok, decoded} = Dcmix.Export.Image.Decoder.decode(dataset, frame: 0, window: :auto)
  """
  @spec decode(DataSet.t(), keyword()) :: {:ok, decoded_image()} | {:error, term()}
  def decode(%DataSet{} = dataset, opts \\ []) do
    frame = Keyword.get(opts, :frame, 0)
    window = Keyword.get(opts, :window, :auto)

    with {:ok, info} <- get_pixel_info(dataset),
         :ok <- validate_not_encapsulated(dataset),
         {:ok, raw_pixels} <- extract_frame(dataset, info, frame),
         {:ok, decoded} <- decode_pixels(raw_pixels, info, window, opts) do
      {:ok, decoded}
    end
  end

  @doc """
  Gets detailed pixel information from a dataset.
  """
  @spec get_pixel_info(DataSet.t()) :: {:ok, pixel_info()} | {:error, term()}
  def get_pixel_info(%DataSet{} = dataset) do
    info = PixelData.info(dataset)

    with {:ok, rows} <- require_value(info.rows, :rows),
         {:ok, columns} <- require_value(info.columns, :columns),
         {:ok, bits_allocated} <- require_value(info.bits_allocated, :bits_allocated),
         {:ok, photometric} <- require_value(info.photometric_interpretation, :photometric) do
      {:ok,
       %{
         rows: rows,
         columns: columns,
         samples_per_pixel: info.samples_per_pixel || 1,
         bits_allocated: bits_allocated,
         bits_stored: info.bits_stored || bits_allocated,
         high_bit: info.high_bit || (bits_allocated - 1),
         pixel_representation: info.pixel_representation || 0,
         photometric_interpretation: String.trim(photometric),
         number_of_frames: info.number_of_frames || 1,
         planar_configuration: DataSet.get_value(dataset, {0x0028, 0x0006})
       }}
    end
  end

  defp require_value(nil, field), do: {:error, {:missing_required_field, field}}
  defp require_value(value, _field), do: {:ok, value}

  defp validate_not_encapsulated(%DataSet{} = dataset) do
    if PixelData.encapsulated?(dataset) do
      {:error, {:compressed_pixel_data, "Decompression not yet supported. Use external tools to decompress first."}}
    else
      :ok
    end
  end

  defp extract_frame(%DataSet{} = dataset, info, frame) do
    frame_size = calculate_frame_size(info)
    total_frames = info.number_of_frames

    if frame >= total_frames do
      {:error, {:invalid_frame, "Frame #{frame} out of range (0-#{total_frames - 1})"}}
    else
      case PixelData.extract(dataset) do
        {:ok, pixels} ->
          offset = frame * frame_size
          frame_data = binary_part(pixels, offset, frame_size)
          {:ok, frame_data}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp calculate_frame_size(info) do
    bytes_per_sample = div(info.bits_allocated, 8)
    info.rows * info.columns * info.samples_per_pixel * bytes_per_sample
  end

  defp decode_pixels(raw_pixels, info, window, opts) do
    photometric = info.photometric_interpretation

    case photometric do
      "MONOCHROME1" ->
        decode_monochrome(raw_pixels, info, window, opts, true)

      "MONOCHROME2" ->
        decode_monochrome(raw_pixels, info, window, opts, false)

      "RGB" ->
        decode_rgb(raw_pixels, info, opts)

      "YBR_FULL" ->
        decode_ybr_full(raw_pixels, info, opts)

      "PALETTE COLOR" ->
        {:error, {:unsupported_photometric, "PALETTE COLOR not yet supported"}}

      other ->
        {:error, {:unsupported_photometric, "Photometric interpretation '#{other}' not supported"}}
    end
  end

  defp decode_monochrome(raw_pixels, info, window, opts, invert) do
    output_bits = Keyword.get(opts, :output_bits)

    # Parse pixel values from binary
    pixel_values = parse_pixel_values(raw_pixels, info)

    # Apply windowing
    {windowed_pixels, actual_output_bits} =
      apply_windowing(pixel_values, info, window, output_bits)

    # Apply inversion for MONOCHROME1
    final_pixels =
      if invert do
        max_val = if actual_output_bits == 8, do: 255, else: 65535
        Enum.map(windowed_pixels, fn v -> max_val - v end)
      else
        windowed_pixels
      end

    # Convert to binary
    pixel_binary = pixels_to_binary(final_pixels, actual_output_bits)

    {:ok,
     %{
       width: info.columns,
       height: info.rows,
       samples_per_pixel: 1,
       bit_depth: actual_output_bits,
       pixels: pixel_binary,
       photometric: :grayscale
     }}
  end

  defp decode_rgb(raw_pixels, info, _opts) do
    if info.samples_per_pixel != 3 do
      {:error, {:invalid_rgb, "RGB requires 3 samples per pixel"}}
    else
      # Handle planar configuration
      pixel_binary =
        case info.planar_configuration do
          1 -> deinterleave_planar(raw_pixels, info)
          _ -> raw_pixels
        end

      # For 8-bit RGB, pass through
      # For 16-bit RGB, scale to 8-bit
      {final_pixels, bit_depth} =
        if info.bits_allocated == 16 do
          {scale_16_to_8(pixel_binary), 8}
        else
          {pixel_binary, 8}
        end

      {:ok,
       %{
         width: info.columns,
         height: info.rows,
         samples_per_pixel: 3,
         bit_depth: bit_depth,
         pixels: final_pixels,
         photometric: :rgb
       }}
    end
  end

  defp decode_ybr_full(raw_pixels, info, _opts) do
    if info.samples_per_pixel != 3 do
      {:error, {:invalid_ybr, "YBR_FULL requires 3 samples per pixel"}}
    else
      # Handle planar configuration first
      interleaved =
        case info.planar_configuration do
          1 -> deinterleave_planar(raw_pixels, info)
          _ -> raw_pixels
        end

      # Convert YCbCr to RGB
      rgb_pixels = ybr_to_rgb(interleaved, info.bits_allocated)

      {:ok,
       %{
         width: info.columns,
         height: info.rows,
         samples_per_pixel: 3,
         bit_depth: 8,
         pixels: rgb_pixels,
         photometric: :rgb
       }}
    end
  end

  # Parse raw binary into list of integer pixel values
  defp parse_pixel_values(binary, info) do
    bytes_per_sample = div(info.bits_allocated, 8)
    signed = info.pixel_representation == 1

    for <<chunk::binary-size(bytes_per_sample) <- binary>> do
      value =
        case {bytes_per_sample, signed} do
          {1, false} -> :binary.decode_unsigned(chunk, :little)
          {1, true} -> decode_signed_8(chunk)
          {2, false} -> :binary.decode_unsigned(chunk, :little)
          {2, true} -> decode_signed_16(chunk)
          _ -> :binary.decode_unsigned(chunk, :little)
        end

      # Mask to bits_stored
      mask = (1 <<< info.bits_stored) - 1
      value = value &&& mask

      # Handle signed values by shifting to unsigned range
      if signed do
        half_range = 1 <<< (info.bits_stored - 1)
        value + half_range
      else
        value
      end
    end
  end

  defp decode_signed_8(<<value::signed-integer-8>>), do: value
  defp decode_signed_16(<<value::signed-little-integer-16>>), do: value

  # Apply windowing to normalize pixel values
  defp apply_windowing(pixel_values, info, window, output_bits) do
    case window do
      :none ->
        # No windowing - preserve original bit depth
        bits = output_bits || 16
        max_out = if bits == 8, do: 255, else: 65535
        max_in = (1 <<< info.bits_stored) - 1
        scaled = Enum.map(pixel_values, fn v -> round(v / max_in * max_out) end)
        {scaled, bits}

      :min_max ->
        # Window based on actual pixel value range
        {min_val, max_val} = Enum.min_max(pixel_values)
        apply_window_transform(pixel_values, min_val, max_val, output_bits || 8)

      :auto ->
        # Try VOI LUT from tags, fall back to min_max
        # For now, use min_max (VOI LUT parsing can be added later)
        {min_val, max_val} = Enum.min_max(pixel_values)
        apply_window_transform(pixel_values, min_val, max_val, output_bits || 8)

      {center, width} ->
        # Explicit window center/width
        min_val = center - width / 2
        max_val = center + width / 2
        apply_window_transform(pixel_values, min_val, max_val, output_bits || 8)
    end
  end

  defp apply_window_transform(pixel_values, min_val, max_val, output_bits) do
    range = max(max_val - min_val, 1)
    max_out = if output_bits == 8, do: 255, else: 65535

    scaled =
      Enum.map(pixel_values, fn v ->
        normalized = (v - min_val) / range
        clamped = max(0.0, min(1.0, normalized))
        round(clamped * max_out)
      end)

    {scaled, output_bits}
  end

  # Convert pixel list to binary
  defp pixels_to_binary(pixels, 8) do
    pixels
    |> Enum.map(fn v -> min(255, max(0, v)) end)
    |> :binary.list_to_bin()
  end

  defp pixels_to_binary(pixels, 16) do
    pixels
    |> Enum.map(fn v ->
      clamped = min(65535, max(0, v))
      <<clamped::little-unsigned-integer-16>>
    end)
    |> IO.iodata_to_binary()
  end

  # Convert planar (RRRGGGBBB) to interleaved (RGBRGBRGB)
  defp deinterleave_planar(binary, info) do
    pixel_count = info.rows * info.columns
    bytes_per_sample = div(info.bits_allocated, 8)
    plane_size = pixel_count * bytes_per_sample

    r_plane = binary_part(binary, 0, plane_size)
    g_plane = binary_part(binary, plane_size, plane_size)
    b_plane = binary_part(binary, plane_size * 2, plane_size)

    r_values = for <<v::binary-size(bytes_per_sample) <- r_plane>>, do: v
    g_values = for <<v::binary-size(bytes_per_sample) <- g_plane>>, do: v
    b_values = for <<v::binary-size(bytes_per_sample) <- b_plane>>, do: v

    [r_values, g_values, b_values]
    |> Enum.zip()
    |> Enum.flat_map(fn {r, g, b} -> [r, g, b] end)
    |> IO.iodata_to_binary()
  end

  # Scale 16-bit RGB to 8-bit
  defp scale_16_to_8(binary) do
    for <<v::little-unsigned-integer-16 <- binary>>, into: <<>> do
      <<div(v, 256)::unsigned-integer-8>>
    end
  end

  # Convert YCbCr to RGB
  defp ybr_to_rgb(binary, bits_allocated) do
    bytes_per_sample = div(bits_allocated, 8)

    pixels =
      for <<y_bin::binary-size(bytes_per_sample),
            cb_bin::binary-size(bytes_per_sample),
            cr_bin::binary-size(bytes_per_sample) <- binary>> do
        y = :binary.decode_unsigned(y_bin, :little)
        cb = :binary.decode_unsigned(cb_bin, :little)
        cr = :binary.decode_unsigned(cr_bin, :little)

        # Scale to 0-255 range if 16-bit
        {y, cb, cr} =
          if bits_allocated == 16 do
            {div(y, 256), div(cb, 256), div(cr, 256)}
          else
            {y, cb, cr}
          end

        # ITU-R BT.601 YCbCr to RGB conversion
        r = round(y + 1.402 * (cr - 128))
        g = round(y - 0.344136 * (cb - 128) - 0.714136 * (cr - 128))
        b = round(y + 1.772 * (cb - 128))

        # Clamp to valid range
        r = max(0, min(255, r))
        g = max(0, min(255, g))
        b = max(0, min(255, b))

        <<r::8, g::8, b::8>>
      end

    IO.iodata_to_binary(pixels)
  end
end
