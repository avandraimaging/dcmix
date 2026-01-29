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
         {:ok, raw_pixels} <- extract_frame(dataset, info, frame) do
      decode_pixels(raw_pixels, info, window, opts)
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
         high_bit: info.high_bit || bits_allocated - 1,
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
      {:error,
       {:compressed_pixel_data,
        "Decompression not yet supported. Use external tools to decompress first."}}
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
        {:error,
         {:unsupported_photometric, "Photometric interpretation '#{other}' not supported"}}
    end
  end

  defp decode_monochrome(raw_pixels, info, window, opts, invert) do
    default_bits = if window == :none, do: 16, else: 8
    output_bits = Keyword.get(opts, :output_bits) || default_bits
    bytes_per_sample = div(info.bits_allocated, 8)
    signed = info.pixel_representation == 1
    mask = (1 <<< info.bits_stored) - 1
    half_range = if signed, do: 1 <<< (info.bits_stored - 1), else: 0

    # Build decode params for reuse
    decode_params = %{bps: bytes_per_sample, signed: signed, mask: mask, half_range: half_range}

    # Compute window parameters (single pass for min_max/auto)
    {min_val, max_val} =
      case window do
        :none -> {0, (1 <<< info.bits_stored) - 1}
        {center, width} -> {center - width / 2, center + width / 2}
        _ -> find_min_max_binary(raw_pixels, decode_params)
      end

    range = max(max_val - min_val, 1)
    max_out = if output_bits == 8, do: 255, else: 65_535

    # Build transform params
    transform = %{min_val: min_val, scale: max_out / range, max_out: max_out, invert: invert}

    # Single pass: parse, window, invert, and output to binary
    pixel_binary = decode_monochrome_binary(raw_pixels, decode_params, transform, output_bits)

    {:ok,
     %{
       width: info.columns,
       height: info.rows,
       samples_per_pixel: 1,
       bit_depth: output_bits,
       pixels: pixel_binary,
       photometric: :grayscale
     }}
  end

  # Decode a single raw pixel value from binary chunk
  defp decode_raw_value(chunk, %{bps: bps, signed: signed}) do
    case {bps, signed} do
      {1, false} -> :binary.decode_unsigned(chunk, :little)
      {1, true} -> decode_signed_8(chunk)
      {2, false} -> :binary.decode_unsigned(chunk, :little)
      {2, true} -> decode_signed_16(chunk)
      _ -> :binary.decode_unsigned(chunk, :little)
    end
  end

  # Find min/max in a single binary scan using reduce with binary generator
  defp find_min_max_binary(binary, %{bps: bps, mask: mask, half_range: half_range} = params) do
    binary
    |> chunk_binary(bps)
    |> Enum.reduce({nil, nil}, fn chunk, {min_acc, max_acc} ->
      value = (decode_raw_value(chunk, params) &&& mask) + half_range
      {min(min_acc || value, value), max(max_acc || value, value)}
    end)
  end

  defp chunk_binary(binary, size) do
    for <<chunk::binary-size(size) <- binary>>, do: chunk
  end

  # Decode monochrome pixels directly to binary output
  defp decode_monochrome_binary(
         binary,
         %{bps: bps, mask: mask, half_range: half_range} = params,
         transform,
         output_bits
       ) do
    %{min_val: min_val, scale: scale, max_out: max_out, invert: invert} = transform

    for <<chunk::binary-size(bps) <- binary>>, into: <<>> do
      value = (decode_raw_value(chunk, params) &&& mask) + half_range
      normalized = (value - min_val) * scale
      clamped = max(0, min(max_out, round(normalized)))
      output = if invert, do: max_out - clamped, else: clamped

      if output_bits == 8, do: <<output::8>>, else: <<output::little-16>>
    end
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

  defp decode_signed_8(<<value::signed-integer-8>>), do: value
  defp decode_signed_16(<<value::signed-little-integer-16>>), do: value

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
      for <<y_bin::binary-size(bytes_per_sample), cb_bin::binary-size(bytes_per_sample),
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
