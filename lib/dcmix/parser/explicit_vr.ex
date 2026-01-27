defmodule Dcmix.Parser.ExplicitVR do
  @moduledoc """
  Parser for Explicit VR transfer syntaxes.

  In Explicit VR encoding, each data element includes the VR as a 2-byte
  ASCII string. The length field is either 2 or 4 bytes depending on the VR.
  """

  alias Dcmix.{Tag, VR, DataElement, DataSet}

  @undefined_length 0xFFFFFFFF

  @doc """
  Parses data elements from binary data using Explicit VR encoding.

  ## Options
  - `:big_endian` - Use big-endian byte ordering (default: false)
  - `:stop_tag` - Stop parsing when this tag is encountered (exclusive)
  """
  @spec parse(binary(), keyword()) :: {:ok, DataSet.t(), binary()} | {:error, term()}
  def parse(data, opts \\ []) do
    big_endian = Keyword.get(opts, :big_endian, false)
    stop_tag = Keyword.get(opts, :stop_tag, nil)

    parse_elements(data, [], big_endian, stop_tag)
  end

  defp parse_elements(<<>>, elements, _big_endian, _stop_tag) do
    {:ok, DataSet.new(Enum.reverse(elements)), <<>>}
  end

  defp parse_elements(data, elements, _big_endian, _stop_tag) when byte_size(data) < 4 do
    {:ok, DataSet.new(Enum.reverse(elements)), data}
  end

  defp parse_elements(data, elements, big_endian, stop_tag) do
    with {:ok, tag, rest} <- parse_tag(data, big_endian),
         :continue <- check_stop_tag(tag, stop_tag),
         {:ok, element, rest} <- parse_element(tag, rest, big_endian) do
      parse_elements(rest, [element | elements], big_endian, stop_tag)
    else
      :stop -> {:ok, DataSet.new(Enum.reverse(elements)), data}
      {:error, _} = error -> error
    end
  end

  defp check_stop_tag(tag, stop_tag) do
    if stop_tag && Tag.compare(tag, stop_tag) != :lt, do: :stop, else: :continue
  end

  defp parse_tag(data, big_endian) do
    case data do
      <<group::16-little, element::16-little, rest::binary>> when not big_endian ->
        {:ok, {group, element}, rest}

      <<group::16-big, element::16-big, rest::binary>> when big_endian ->
        {:ok, {group, element}, rest}

      _ ->
        {:error, :unexpected_eof}
    end
  end

  defp parse_element(tag, data, big_endian) do
    # Item delimiters don't have VR
    if Tag.item_tag?(tag) do
      parse_item_tag(tag, data, big_endian)
    else
      parse_data_element(tag, data, big_endian)
    end
  end

  defp parse_item_tag(tag, data, big_endian) do
    case read_uint32(data, big_endian) do
      {:ok, length, rest} ->
        {:ok, DataElement.new(tag, nil, nil, length), rest}

      {:error, _} = error ->
        error
    end
  end

  defp parse_data_element(tag, data, big_endian) do
    case data do
      <<vr_bytes::binary-size(2), rest::binary>> ->
        case VR.parse(vr_bytes) do
          {:ok, vr} ->
            parse_value(tag, vr, rest, big_endian)

          {:error, _} ->
            # Unknown VR - treat as UN
            parse_value(tag, :UN, rest, big_endian)
        end

      _ ->
        {:error, :unexpected_eof}
    end
  end

  defp parse_value(tag, vr, data, big_endian) do
    if VR.long_length?(vr) do
      parse_long_value(tag, vr, data, big_endian)
    else
      parse_short_value(tag, vr, data, big_endian)
    end
  end

  # Short length format: 2-byte length immediately after VR
  defp parse_short_value(tag, vr, data, big_endian) do
    case read_uint16(data, big_endian) do
      {:ok, length, rest} ->
        read_value(tag, vr, length, rest, big_endian)

      {:error, _} = error ->
        error
    end
  end

  # Long length format: 2-byte reserved + 4-byte length
  defp parse_long_value(tag, vr, data, big_endian) do
    case data do
      <<_reserved::16, rest::binary>> ->
        case read_uint32(rest, big_endian) do
          {:ok, length, rest} ->
            read_value(tag, vr, length, rest, big_endian)

          {:error, _} = error ->
            error
        end

      _ ->
        {:error, :unexpected_eof}
    end
  end

  defp read_value(tag, vr, @undefined_length, data, big_endian) do
    # Undefined length - must be SQ or encapsulated pixel data
    if vr == :SQ do
      parse_sequence(tag, vr, data, big_endian)
    else
      # Encapsulated pixel data or UN with undefined length
      parse_encapsulated_value(tag, vr, data, big_endian)
    end
  end

  defp read_value(tag, vr, length, data, big_endian) when byte_size(data) >= length do
    <<value_bytes::binary-size(length), rest::binary>> = data
    value = decode_value(vr, value_bytes, big_endian)
    {:ok, DataElement.new(tag, vr, value, length), rest}
  end

  defp read_value(_tag, _vr, _length, _data, _big_endian) do
    {:error, :unexpected_eof}
  end

  defp parse_sequence(tag, vr, data, big_endian) do
    case parse_sequence_items(data, [], big_endian) do
      {:ok, items, rest} ->
        {:ok, DataElement.new(tag, vr, items, :undefined), rest}

      {:error, _} = error ->
        error
    end
  end

  defp parse_sequence_items(data, items, big_endian) do
    with {:ok, tag, rest} <- parse_tag(data, big_endian) do
      handle_sequence_tag(tag, rest, items, big_endian)
    end
  end

  defp handle_sequence_tag({0xFFFE, 0xE0DD}, rest, items, big_endian) do
    # Sequence Delimitation Item
    with {:ok, _length, rest} <- read_uint32(rest, big_endian) do
      {:ok, Enum.reverse(items), rest}
    end
  end

  defp handle_sequence_tag({0xFFFE, 0xE000}, rest, items, big_endian) do
    # Item tag
    with {:ok, length, rest} <- read_uint32(rest, big_endian),
         {:ok, item_ds, rest} <- parse_item(length, rest, big_endian) do
      parse_sequence_items(rest, [item_ds | items], big_endian)
    end
  end

  defp handle_sequence_tag(tag, _rest, _items, _big_endian) do
    {:error, {:unexpected_tag_in_sequence, tag}}
  end

  defp parse_item(@undefined_length, data, big_endian) do
    # Parse until Item Delimitation Item
    parse_item_undefined(data, [], big_endian)
  end

  defp parse_item(length, data, big_endian) when byte_size(data) >= length do
    <<item_data::binary-size(length), rest::binary>> = data
    # Recursively parse item contents
    case parse(item_data, big_endian: big_endian) do
      {:ok, ds, _remaining} -> {:ok, ds, rest}
      {:error, _} = error -> error
    end
  end

  defp parse_item(_length, _data, _big_endian) do
    {:error, :unexpected_eof}
  end

  defp parse_item_undefined(data, elements, big_endian) do
    case parse_tag(data, big_endian) do
      {:ok, {0xFFFE, 0xE00D}, rest} ->
        # Item Delimitation Item
        case read_uint32(rest, big_endian) do
          {:ok, _length, rest} ->
            {:ok, DataSet.new(Enum.reverse(elements)), rest}

          {:error, _} = error ->
            error
        end

      {:ok, tag, rest} ->
        case parse_element(tag, rest, big_endian) do
          {:ok, element, rest} ->
            parse_item_undefined(rest, [element | elements], big_endian)

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp parse_encapsulated_value(tag, vr, data, big_endian) do
    # Parse encapsulated data (fragments) until sequence delimitation
    case parse_fragments(data, [], big_endian) do
      {:ok, fragments, rest} ->
        # Store as list of fragment binaries
        {:ok, DataElement.new(tag, vr, fragments, :undefined), rest}

      {:error, _} = error ->
        error
    end
  end

  defp parse_fragments(data, fragments, big_endian) do
    with {:ok, tag, rest} <- parse_tag(data, big_endian) do
      handle_fragment_tag(tag, rest, fragments, big_endian)
    end
  end

  defp handle_fragment_tag({0xFFFE, 0xE0DD}, rest, fragments, big_endian) do
    # Sequence Delimitation Item
    with {:ok, _length, rest} <- read_uint32(rest, big_endian) do
      {:ok, Enum.reverse(fragments), rest}
    end
  end

  defp handle_fragment_tag({0xFFFE, 0xE000}, rest, fragments, big_endian) do
    # Item (fragment)
    with {:ok, length, rest} <- read_uint32(rest, big_endian),
         {:ok, fragment, rest} <- extract_fragment(length, rest) do
      parse_fragments(rest, [fragment | fragments], big_endian)
    end
  end

  defp handle_fragment_tag(tag, _rest, _fragments, _big_endian) do
    {:error, {:unexpected_tag_in_encapsulated, tag}}
  end

  defp extract_fragment(length, rest) when byte_size(rest) >= length do
    <<fragment::binary-size(length), remaining::binary>> = rest
    {:ok, fragment, remaining}
  end

  defp extract_fragment(_length, _rest), do: {:error, :unexpected_eof}

  defp decode_value(:SQ, _bytes, _big_endian) do
    # SQ is handled separately with defined length
    []
  end

  defp decode_value(vr, bytes, big_endian) when vr in [:US, :SS, :UL, :SL, :FL, :FD, :AT] do
    decode_numeric(vr, bytes, big_endian)
  end

  defp decode_value(vr, bytes, _big_endian) when vr in [:OB, :OW, :OD, :OF, :OL, :UN] do
    # Binary data - return as-is
    bytes
  end

  defp decode_value(_vr, bytes, _big_endian) do
    # String types - trim padding
    bytes
    |> String.trim_trailing(<<0>>)
    |> String.trim_trailing(" ")
  end

  defp decode_numeric(:US, bytes, big_endian) do
    decode_uint16_list(bytes, big_endian)
  end

  defp decode_numeric(:SS, bytes, big_endian) do
    decode_int16_list(bytes, big_endian)
  end

  defp decode_numeric(:UL, bytes, big_endian) do
    decode_uint32_list(bytes, big_endian)
  end

  defp decode_numeric(:SL, bytes, big_endian) do
    decode_int32_list(bytes, big_endian)
  end

  defp decode_numeric(:FL, bytes, big_endian) do
    decode_float32_list(bytes, big_endian)
  end

  defp decode_numeric(:FD, bytes, big_endian) do
    decode_float64_list(bytes, big_endian)
  end

  defp decode_numeric(:AT, bytes, big_endian) do
    # Attribute Tag - list of tags
    decode_tag_list(bytes, big_endian)
  end

  defp decode_uint16_list(bytes, big_endian, acc \\ [])
  defp decode_uint16_list(<<>>, _big_endian, acc), do: unwrap_single(Enum.reverse(acc))

  defp decode_uint16_list(<<val::16-little, rest::binary>>, false, acc),
    do: decode_uint16_list(rest, false, [val | acc])

  defp decode_uint16_list(<<val::16-big, rest::binary>>, true, acc),
    do: decode_uint16_list(rest, true, [val | acc])

  defp decode_int16_list(bytes, big_endian, acc \\ [])
  defp decode_int16_list(<<>>, _big_endian, acc), do: unwrap_single(Enum.reverse(acc))

  defp decode_int16_list(<<val::16-signed-little, rest::binary>>, false, acc),
    do: decode_int16_list(rest, false, [val | acc])

  defp decode_int16_list(<<val::16-signed-big, rest::binary>>, true, acc),
    do: decode_int16_list(rest, true, [val | acc])

  defp decode_uint32_list(bytes, big_endian, acc \\ [])
  defp decode_uint32_list(<<>>, _big_endian, acc), do: unwrap_single(Enum.reverse(acc))

  defp decode_uint32_list(<<val::32-little, rest::binary>>, false, acc),
    do: decode_uint32_list(rest, false, [val | acc])

  defp decode_uint32_list(<<val::32-big, rest::binary>>, true, acc),
    do: decode_uint32_list(rest, true, [val | acc])

  defp decode_int32_list(bytes, big_endian, acc \\ [])
  defp decode_int32_list(<<>>, _big_endian, acc), do: unwrap_single(Enum.reverse(acc))

  defp decode_int32_list(<<val::32-signed-little, rest::binary>>, false, acc),
    do: decode_int32_list(rest, false, [val | acc])

  defp decode_int32_list(<<val::32-signed-big, rest::binary>>, true, acc),
    do: decode_int32_list(rest, true, [val | acc])

  defp decode_float32_list(bytes, big_endian, acc \\ [])
  defp decode_float32_list(<<>>, _big_endian, acc), do: unwrap_single(Enum.reverse(acc))

  defp decode_float32_list(<<val::32-float-little, rest::binary>>, false, acc),
    do: decode_float32_list(rest, false, [val | acc])

  defp decode_float32_list(<<val::32-float-big, rest::binary>>, true, acc),
    do: decode_float32_list(rest, true, [val | acc])

  defp decode_float64_list(bytes, big_endian, acc \\ [])
  defp decode_float64_list(<<>>, _big_endian, acc), do: unwrap_single(Enum.reverse(acc))

  defp decode_float64_list(<<val::64-float-little, rest::binary>>, false, acc),
    do: decode_float64_list(rest, false, [val | acc])

  defp decode_float64_list(<<val::64-float-big, rest::binary>>, true, acc),
    do: decode_float64_list(rest, true, [val | acc])

  defp decode_tag_list(bytes, big_endian, acc \\ [])
  defp decode_tag_list(<<>>, _big_endian, acc), do: unwrap_single(Enum.reverse(acc))

  defp decode_tag_list(<<g::16-little, e::16-little, rest::binary>>, false, acc),
    do: decode_tag_list(rest, false, [{g, e} | acc])

  defp decode_tag_list(<<g::16-big, e::16-big, rest::binary>>, true, acc),
    do: decode_tag_list(rest, true, [{g, e} | acc])

  # Unwrap single-element lists
  defp unwrap_single([single]), do: single
  defp unwrap_single(list), do: list

  defp read_uint16(data, big_endian) do
    case data do
      <<val::16-little, rest::binary>> when not big_endian -> {:ok, val, rest}
      <<val::16-big, rest::binary>> when big_endian -> {:ok, val, rest}
      _ -> {:error, :unexpected_eof}
    end
  end

  defp read_uint32(data, big_endian) do
    case data do
      <<val::32-little, rest::binary>> when not big_endian -> {:ok, val, rest}
      <<val::32-big, rest::binary>> when big_endian -> {:ok, val, rest}
      _ -> {:error, :unexpected_eof}
    end
  end
end
