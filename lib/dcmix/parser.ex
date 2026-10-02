defmodule Dcmix.Parser do
  @moduledoc """
  DICOM file parser.

  Parses DICOM Part 10 files, handling:
  - 128-byte preamble
  - "DICM" prefix
  - File Meta Information (always Explicit VR Little Endian)
  - Dataset (transfer syntax from File Meta Information)
  """

  alias Dcmix.{Tag, DataSet}
  alias Dcmix.Parser.{TransferSyntax, ExplicitVR, ImplicitVR}

  @preamble_size 128
  @dicm_prefix "DICM"

  # Float Pixel Data (7FE0,0008) is the lowest of the three pixel data tags, so
  # stopping at it or anything after skips Float, Double Float and Pixel Data.
  @pixel_data_start {0x7FE0, 0x0008}
  @default_read_size 65_536

  @doc """
  Parses a DICOM file from the filesystem.

  ## Options
  - `:force_transfer_syntax` - Override the transfer syntax from file meta
  - `:stop_before_pixels` - Stop at the first top-level pixel data element
    (Float, Double Float or Pixel Data) and return everything before it. The
    file is read only as far as that element, so a large image costs no more
    than its header. Elements after the pixel data are not read.
  - `:read_size` - With `:stop_before_pixels`, how many bytes to read first
    (default 64 KiB). The read doubles until the pixel data is reached.

  ## Examples

      iex> Dcmix.Parser.parse_file("/path/to/file.dcm")
      {:ok, %Dcmix.DataSet{}}
  """
  @spec parse_file(Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def parse_file(path, opts \\ []) do
    if Keyword.get(opts, :stop_before_pixels, false) do
      parse_file_before_pixels(path, opts)
    else
      case File.read(path) do
        {:ok, data} -> parse(data, opts)
        {:error, reason} -> {:error, {:file_error, reason}}
      end
    end
  end

  defp parse_file_before_pixels(path, opts) do
    read_size = max(Keyword.get(opts, :read_size, @default_read_size), @preamble_size + 4)

    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        try do
          read_until_pixels(file, <<>>, read_size, opts)
        after
          File.close(file)
        end

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  # Everything before a stop was parsed from bytes actually read, so a stop is
  # final. Anything short of one -- an error from a value cut off mid-read, or
  # running out of data -- only means more of the file is needed.
  defp read_until_pixels(file, data, read_size, opts) do
    case IO.binread(file, read_size) do
      :eof ->
        parse(data, opts)

      {:error, reason} ->
        {:error, {:file_error, reason}}

      chunk when byte_size(chunk) < read_size ->
        parse(data <> chunk, opts)

      chunk ->
        data = data <> chunk

        case parse_binary(data, opts) do
          {:ok, dataset, :stopped} -> {:ok, dataset}
          _incomplete -> read_until_pixels(file, data, byte_size(data), opts)
        end
    end
  end

  @doc """
  Parses DICOM data from binary.

  ## Options
  - `:force_transfer_syntax` - Override the transfer syntax
  - `:stop_before_pixels` - Stop at the first top-level pixel data element
  """
  @spec parse(binary(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def parse(data, opts \\ []) do
    case parse_binary(data, opts) do
      {:ok, dataset, _status} -> {:ok, dataset}
      {:error, _} = error -> error
    end
  end

  defp parse_binary(data, opts) do
    case check_dicm_prefix(data) do
      {:ok, rest} ->
        parse_part10(rest, opts)

      {:error, :no_dicm_prefix} ->
        # Try parsing without preamble (raw dataset)
        parse_raw(data, opts)
    end
  end

  defp check_dicm_prefix(data) when byte_size(data) >= @preamble_size + 4 do
    <<_preamble::binary-size(@preamble_size), prefix::binary-size(4), rest::binary>> = data

    if prefix == @dicm_prefix do
      {:ok, rest}
    else
      {:error, :no_dicm_prefix}
    end
  end

  defp check_dicm_prefix(_data), do: {:error, :no_dicm_prefix}

  defp parse_part10(data, opts) do
    # File Meta Information is always Explicit VR Little Endian
    case parse_file_meta(data) do
      {:ok, file_meta, rest} ->
        transfer_syntax_uid = get_transfer_syntax_uid(file_meta, opts)

        case parse_dataset(rest, transfer_syntax_uid, stop_tag(opts)) do
          {:ok, dataset, status} ->
            # Merge file meta with dataset
            {:ok, DataSet.merge(file_meta, dataset), status}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp parse_file_meta(data) do
    # Parse File Meta elements (group 0002) using Explicit VR Little Endian
    # Stop at first non-file-meta tag
    case ExplicitVR.parse(data, stop_tag: {0x0003, 0x0000}) do
      {:ok, dataset, rest} ->
        # Filter to only file meta elements
        file_meta_elements =
          dataset
          |> DataSet.to_list()
          |> Enum.filter(fn e -> Tag.file_meta?(e.tag) end)

        {:ok, DataSet.new(file_meta_elements), rest}

      {:error, _} = error ->
        error
    end
  end

  defp get_transfer_syntax_uid(file_meta, opts) do
    case Keyword.get(opts, :force_transfer_syntax) do
      nil ->
        case DataSet.get_value(file_meta, Tag.transfer_syntax_uid()) do
          nil -> TransferSyntax.explicit_vr_little_endian()
          uid -> uid
        end

      uid ->
        uid
    end
  end

  defp stop_tag(opts) do
    if Keyword.get(opts, :stop_before_pixels, false), do: @pixel_data_start
  end

  defp parse_dataset(data, transfer_syntax_uid, stop_tag) do
    {explicit_vr, big_endian} = encoding(transfer_syntax_uid)

    result =
      if explicit_vr do
        ExplicitVR.parse(data, big_endian: big_endian, stop_tag: stop_tag)
      else
        ImplicitVR.parse(data, stop_tag: stop_tag)
      end

    case result do
      {:ok, dataset, remaining} -> {:ok, dataset, status(remaining, big_endian, stop_tag)}
      {:error, _} = error -> error
    end
  end

  defp encoding(transfer_syntax_uid) do
    case TransferSyntax.lookup(transfer_syntax_uid) do
      {:ok, ts} -> {ts.explicit_vr, ts.big_endian}
      # Default to Explicit VR Little Endian for unknown
      {:error, :unknown_transfer_syntax} -> {true, false}
    end
  end

  # The parsers hand back unparsed bytes both when they stop and when the data
  # runs out, so a stop is told apart by the tag the remaining bytes start with.
  defp status(_remaining, _big_endian, nil), do: :complete

  defp status(<<group::16-little, element::16-little, _::binary>>, false, stop_tag),
    do: stopped_at(stop_tag, {group, element})

  defp status(<<group::16-big, element::16-big, _::binary>>, true, stop_tag),
    do: stopped_at(stop_tag, {group, element})

  defp status(_remaining, _big_endian, _stop_tag), do: :complete

  defp stopped_at(stop_tag, tag) do
    if Tag.compare(tag, stop_tag) == :lt, do: :complete, else: :stopped
  end

  defp parse_raw(data, opts) do
    # Try to parse as raw dataset without file meta
    transfer_syntax_uid =
      Keyword.get(opts, :force_transfer_syntax, TransferSyntax.explicit_vr_little_endian())

    case parse_dataset(data, transfer_syntax_uid, stop_tag(opts)) do
      {:ok, dataset, status} ->
        {:ok, dataset, status}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Parses only the file meta information from a DICOM file.
  Useful for quick inspection without parsing the full dataset.
  """
  @spec parse_file_meta_only(Path.t()) :: {:ok, DataSet.t()} | {:error, term()}
  def parse_file_meta_only(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        try do
          read_and_parse_file_meta(file)
        after
          File.close(file)
        end

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  defp read_and_parse_file_meta(file) do
    case IO.binread(file, @preamble_size + 4 + 4096) do
      data when is_binary(data) -> parse_file_meta_from_data(data)
      {:error, reason} -> {:error, {:file_error, reason}}
      :eof -> {:error, :unexpected_eof}
    end
  end

  defp parse_file_meta_from_data(data) do
    with {:ok, rest} <- check_dicm_prefix(data),
         {:ok, file_meta, _} <- parse_file_meta(rest) do
      {:ok, file_meta}
    end
  end

  @doc """
  Returns the transfer syntax UID from a DICOM file without parsing the full dataset.
  """
  @spec get_transfer_syntax(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def get_transfer_syntax(path) do
    case parse_file_meta_only(path) do
      {:ok, file_meta} ->
        case DataSet.get_value(file_meta, Tag.transfer_syntax_uid()) do
          nil -> {:error, :no_transfer_syntax}
          uid -> {:ok, uid}
        end

      {:error, _} = error ->
        error
    end
  end
end
