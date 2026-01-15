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

  @doc """
  Parses a DICOM file from the filesystem.

  ## Options
  - `:force_transfer_syntax` - Override the transfer syntax from file meta

  ## Examples

      iex> Dcmix.Parser.parse_file("/path/to/file.dcm")
      {:ok, %Dcmix.DataSet{}}
  """
  @spec parse_file(Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def parse_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, data} -> parse(data, opts)
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  @doc """
  Parses DICOM data from binary.

  ## Options
  - `:force_transfer_syntax` - Override the transfer syntax
  """
  @spec parse(binary(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def parse(data, opts \\ []) do
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

        case parse_dataset(rest, transfer_syntax_uid) do
          {:ok, dataset, _remaining} ->
            # Merge file meta with dataset
            {:ok, DataSet.merge(file_meta, dataset)}

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

  defp parse_dataset(data, transfer_syntax_uid) do
    case TransferSyntax.lookup(transfer_syntax_uid) do
      {:ok, ts} ->
        if ts.explicit_vr do
          ExplicitVR.parse(data, big_endian: ts.big_endian)
        else
          ImplicitVR.parse(data)
        end

      {:error, :unknown_transfer_syntax} ->
        # Default to Explicit VR Little Endian for unknown
        ExplicitVR.parse(data, big_endian: false)
    end
  end

  defp parse_raw(data, opts) do
    # Try to parse as raw dataset without file meta
    transfer_syntax_uid =
      Keyword.get(opts, :force_transfer_syntax, TransferSyntax.explicit_vr_little_endian())

    case parse_dataset(data, transfer_syntax_uid) do
      {:ok, dataset, _remaining} ->
        {:ok, dataset}

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
    # Read just enough to get file meta (typically < 1KB)
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        result =
          try do
            # Read preamble + prefix + some file meta
            case IO.binread(file, @preamble_size + 4 + 4096) do
              data when is_binary(data) ->
                case check_dicm_prefix(data) do
                  {:ok, rest} ->
                    case parse_file_meta(rest) do
                      {:ok, file_meta, _} -> {:ok, file_meta}
                      {:error, _} = error -> error
                    end

                  {:error, _} = error ->
                    error
                end

              {:error, reason} ->
                {:error, {:file_error, reason}}

              :eof ->
                {:error, :unexpected_eof}
            end
          after
            File.close(file)
          end

        result

      {:error, reason} ->
        {:error, {:file_error, reason}}
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
