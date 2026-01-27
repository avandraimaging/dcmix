defmodule Dcmix.PixelData do
  @moduledoc """
  Utilities for extracting and injecting pixel data in DICOM files.

  This module provides functions to extract raw pixel data from a DataSet
  and inject pixel data back into a DataSet. It does not perform any
  image processing - that should be done by external tools.

  ## Pixel Data Formats

  DICOM pixel data can be stored in two formats:

  1. **Native (uncompressed)** - Raw pixel values stored contiguously
  2. **Encapsulated (compressed)** - Data stored as fragments, usually compressed

  For compressed data (JPEG, JPEG2000, etc.), external tools are needed
  for decompression. This module extracts the raw bytes as-is.

  ## Usage

      # Extract pixel data from a dataset
      {:ok, pixel_data} = Dcmix.PixelData.extract(dataset)

      # Save to file for external processing
      File.write!("pixels.raw", pixel_data)

      # Process externally...

      # Inject back into dataset
      new_pixel_data = File.read!("pixels_modified.raw")
      dataset = Dcmix.PixelData.inject(dataset, new_pixel_data)
  """

  alias Dcmix.{Tag, DataSet, DataElement}

  @pixel_data_tag {0x7FE0, 0x0010}

  @doc """
  Extracts pixel data from a DataSet.

  Returns the raw bytes of the pixel data. For encapsulated (compressed)
  data, returns the concatenated fragments.

  ## Options
  - `:include_offset_table` - Include the offset table for encapsulated data (default: false)

  ## Examples

      {:ok, pixel_bytes} = Dcmix.PixelData.extract(dataset)
  """
  @spec extract(DataSet.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def extract(%DataSet{} = dataset, opts \\ []) do
    case DataSet.get(dataset, @pixel_data_tag) do
      nil ->
        {:error, :no_pixel_data}

      %DataElement{value: value} when is_binary(value) ->
        {:ok, value}

      %DataElement{value: fragments} when is_list(fragments) ->
        # Encapsulated pixel data - concatenate fragments
        include_offset_table = Keyword.get(opts, :include_offset_table, false)

        if include_offset_table do
          {:ok, IO.iodata_to_binary(fragments)}
        else
          # Skip first fragment (offset table) if present
          data_fragments = if length(fragments) > 1, do: tl(fragments), else: fragments
          {:ok, IO.iodata_to_binary(data_fragments)}
        end

      %DataElement{value: nil} ->
        {:error, :empty_pixel_data}
    end
  end

  @doc """
  Extracts individual frames from encapsulated pixel data.

  For multi-frame images with encapsulated pixel data, this returns
  a list of binaries, one per fragment (typically one per frame,
  but this depends on the compression scheme).

  ## Examples

      {:ok, frames} = Dcmix.PixelData.extract_frames(dataset)
  """
  @spec extract_frames(DataSet.t()) :: {:ok, [binary()]} | {:error, term()}
  def extract_frames(%DataSet{} = dataset) do
    case DataSet.get(dataset, @pixel_data_tag) do
      nil ->
        {:error, :no_pixel_data}

      %DataElement{value: value} when is_binary(value) ->
        # Native pixel data - single "frame" (or needs frame-by-frame parsing)
        {:ok, [value]}

      %DataElement{value: fragments} when is_list(fragments) ->
        # Skip offset table (first fragment)
        data_fragments = if length(fragments) > 1, do: tl(fragments), else: fragments
        {:ok, data_fragments}

      %DataElement{value: nil} ->
        {:error, :empty_pixel_data}
    end
  end

  @doc """
  Injects pixel data into a DataSet.

  Replaces the pixel data in the dataset with the provided binary data.
  For native (uncompressed) data, the VR will be OW.

  ## Options
  - `:vr` - Value Representation to use (default: :OW)

  ## Examples

      dataset = Dcmix.PixelData.inject(dataset, new_pixel_bytes)
  """
  @spec inject(DataSet.t(), binary(), keyword()) :: DataSet.t()
  def inject(%DataSet{} = dataset, pixel_data, opts \\ []) when is_binary(pixel_data) do
    vr = Keyword.get(opts, :vr, :OW)
    element = DataElement.new(@pixel_data_tag, vr, pixel_data)
    DataSet.put(dataset, element)
  end

  @doc """
  Injects encapsulated (compressed) pixel data into a DataSet.

  Takes a list of frame binaries and creates encapsulated pixel data
  with proper fragment structure.

  ## Options
  - `:vr` - Value Representation to use (default: :OB for encapsulated)
  - `:offset_table` - Binary offset table (default: empty)

  ## Examples

      frames = [frame1_bytes, frame2_bytes, frame3_bytes]
      dataset = Dcmix.PixelData.inject_encapsulated(dataset, frames)
  """
  @spec inject_encapsulated(DataSet.t(), [binary()], keyword()) :: DataSet.t()
  def inject_encapsulated(%DataSet{} = dataset, frames, opts \\ []) when is_list(frames) do
    vr = Keyword.get(opts, :vr, :OB)
    offset_table = Keyword.get(opts, :offset_table, <<>>)

    # Build fragments list: offset table first, then data frames
    fragments = [offset_table | frames]

    element = DataElement.new(@pixel_data_tag, vr, fragments, :undefined)
    DataSet.put(dataset, element)
  end

  @doc """
  Returns information about the pixel data in a DataSet.

  ## Examples

      info = Dcmix.PixelData.info(dataset)
      # => %{rows: 512, columns: 512, bits_allocated: 16, ...}
  """
  @spec info(DataSet.t()) :: map()
  def info(%DataSet{} = dataset) do
    %{
      rows: DataSet.get_value(dataset, Tag.rows()),
      columns: DataSet.get_value(dataset, Tag.columns()),
      samples_per_pixel: DataSet.get_value(dataset, Tag.samples_per_pixel()) || 1,
      bits_allocated: DataSet.get_value(dataset, Tag.bits_allocated()),
      bits_stored: DataSet.get_value(dataset, Tag.bits_stored()),
      high_bit: DataSet.get_value(dataset, Tag.high_bit()),
      pixel_representation: DataSet.get_value(dataset, Tag.pixel_representation()),
      photometric_interpretation:
        DataSet.get_value(dataset, Tag.photometric_interpretation()),
      number_of_frames: parse_int(DataSet.get_value(dataset, {0x0028, 0x0008})) || 1,
      has_pixel_data: DataSet.has_tag?(dataset, @pixel_data_tag),
      encapsulated: is_encapsulated?(dataset)
    }
  end

  @doc """
  Returns the expected size of native pixel data in bytes.

  Calculates based on rows, columns, samples per pixel, bits allocated,
  and number of frames.
  """
  @spec expected_size(DataSet.t()) :: non_neg_integer() | nil
  def expected_size(%DataSet{} = dataset) do
    pixel_info = info(dataset)

    with rows when is_integer(rows) <- pixel_info.rows,
         cols when is_integer(cols) <- pixel_info.columns,
         bits when is_integer(bits) <- pixel_info.bits_allocated do
      bytes_per_pixel = div(bits, 8)
      samples = pixel_info.samples_per_pixel || 1
      frames = pixel_info.number_of_frames || 1

      rows * cols * samples * bytes_per_pixel * frames
    else
      _ -> nil
    end
  end

  @doc """
  Returns true if the pixel data is encapsulated (compressed).
  """
  @spec is_encapsulated?(DataSet.t()) :: boolean()
  def is_encapsulated?(%DataSet{} = dataset) do
    case DataSet.get(dataset, @pixel_data_tag) do
      %DataElement{value: fragments} when is_list(fragments) -> true
      _ -> false
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
