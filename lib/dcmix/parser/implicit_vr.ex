defmodule Dcmix.Parser.ImplicitVR do
  @moduledoc """
  Parser for Implicit VR Little Endian transfer syntax.

  In Implicit VR encoding, elements don't include the VR in the data.
  The VR must be looked up from the data dictionary. All elements use
  a 4-byte length field, and byte ordering is always little-endian.
  """

  alias Dcmix.{Tag, DataElement, DataSet, Dictionary}

  @undefined_length 0xFFFFFFFF

  @doc """
  Parses data elements from binary data using Implicit VR encoding.

  ## Options
  - `:stop_tag` - Stop parsing when this tag is encountered (exclusive)
  """
  @spec parse(binary(), keyword()) :: {:ok, DataSet.t(), binary()} | {:error, term()}
  def parse(data, opts \\ []) do
    stop_tag = Keyword.get(opts, :stop_tag, nil)
    parse_elements(data, [], stop_tag)
  end

  defp parse_elements(<<>>, elements, _stop_tag) do
    {:ok, DataSet.new(Enum.reverse(elements)), <<>>}
  end

  defp parse_elements(data, elements, _stop_tag) when byte_size(data) < 8 do
    {:ok, DataSet.new(Enum.reverse(elements)), data}
  end

  defp parse_elements(data, elements, stop_tag) do
    case parse_tag(data) do
      {:ok, tag, rest} ->
        if stop_tag && Tag.compare(tag, stop_tag) != :lt do
          {:ok, DataSet.new(Enum.reverse(elements)), data}
        else
          case parse_element(tag, rest) do
            {:ok, element, rest} ->
              parse_elements(rest, [element | elements], stop_tag)

            {:error, _} = error ->
              error
          end
        end

      {:error, _} = error ->
        error
    end
  end

  defp parse_tag(<<group::16-little, element::16-little, rest::binary>>) do
    {:ok, {group, element}, rest}
  end

  defp parse_tag(_), do: {:error, :unexpected_eof}

  defp parse_element(tag, data) do
    case data do
      <<length::32-little, rest::binary>> ->
        vr = lookup_vr(tag)
        read_value(tag, vr, length, rest)

      _ ->
        {:error, :unexpected_eof}
    end
  end

  defp lookup_vr(tag) do
    # Item delimiters don't have VR
    if Tag.item_tag?(tag) do
      nil
    else
      Dictionary.vr(tag) || :UN
    end
  end

  defp read_value(tag, vr, @undefined_length, data) do
    # Undefined length - could be SQ
    if vr == :SQ do
      parse_sequence(tag, vr, data)
    else
      # Try to parse as sequence anyway (common for UN with undefined length)
      parse_sequence(tag, vr, data)
    end
  end

  defp read_value(tag, vr, length, data) when byte_size(data) >= length do
    <<value_bytes::binary-size(length), rest::binary>> = data

    # Check if this might be a sequence with defined length
    if vr == :SQ and length > 0 do
      case parse_sequence_defined(value_bytes) do
        {:ok, items} ->
          {:ok, DataElement.new(tag, vr, items, length), rest}

        {:error, _} ->
          # Not a valid sequence, treat as binary
          value = decode_value(vr, value_bytes)
          {:ok, DataElement.new(tag, vr, value, length), rest}
      end
    else
      value = decode_value(vr, value_bytes)
      {:ok, DataElement.new(tag, vr, value, length), rest}
    end
  end

  defp read_value(_tag, _vr, _length, _data) do
    {:error, :unexpected_eof}
  end

  defp parse_sequence(tag, vr, data) do
    case parse_sequence_items(data, []) do
      {:ok, items, rest} ->
        {:ok, DataElement.new(tag, vr || :SQ, items, :undefined), rest}

      {:error, _} = error ->
        error
    end
  end

  defp parse_sequence_items(data, items) do
    case parse_tag(data) do
      {:ok, {0xFFFE, 0xE0DD}, rest} ->
        # Sequence Delimitation Item
        case rest do
          <<_length::32-little, rest::binary>> ->
            {:ok, Enum.reverse(items), rest}

          _ ->
            {:error, :unexpected_eof}
        end

      {:ok, {0xFFFE, 0xE000}, rest} ->
        # Item tag
        case rest do
          <<length::32-little, rest::binary>> ->
            case parse_item(length, rest) do
              {:ok, item_ds, rest} ->
                parse_sequence_items(rest, [item_ds | items])

              {:error, _} = error ->
                error
            end

          _ ->
            {:error, :unexpected_eof}
        end

      {:ok, tag, _rest} ->
        {:error, {:unexpected_tag_in_sequence, tag}}

      {:error, _} = error ->
        error
    end
  end

  defp parse_sequence_defined(data) do
    parse_sequence_items_defined(data, [])
  end

  defp parse_sequence_items_defined(<<>>, items) do
    {:ok, Enum.reverse(items)}
  end

  defp parse_sequence_items_defined(data, items) do
    case parse_tag(data) do
      {:ok, {0xFFFE, 0xE000}, rest} ->
        case rest do
          <<length::32-little, rest::binary>> ->
            case parse_item(length, rest) do
              {:ok, item_ds, rest} ->
                parse_sequence_items_defined(rest, [item_ds | items])

              {:error, _} = error ->
                error
            end

          _ ->
            {:error, :unexpected_eof}
        end

      {:ok, _tag, _rest} ->
        {:error, :not_a_sequence}

      {:error, _} = error ->
        error
    end
  end

  defp parse_item(@undefined_length, data) do
    parse_item_undefined(data, [])
  end

  defp parse_item(length, data) when byte_size(data) >= length do
    <<item_data::binary-size(length), rest::binary>> = data

    case parse(item_data) do
      {:ok, ds, _remaining} -> {:ok, ds, rest}
      {:error, _} = error -> error
    end
  end

  defp parse_item(_length, _data) do
    {:error, :unexpected_eof}
  end

  defp parse_item_undefined(data, elements) do
    case parse_tag(data) do
      {:ok, {0xFFFE, 0xE00D}, rest} ->
        # Item Delimitation Item
        case rest do
          <<_length::32-little, rest::binary>> ->
            {:ok, DataSet.new(Enum.reverse(elements)), rest}

          _ ->
            {:error, :unexpected_eof}
        end

      {:ok, tag, rest} ->
        case parse_element(tag, rest) do
          {:ok, element, rest} ->
            parse_item_undefined(rest, [element | elements])

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp decode_value(:SQ, _bytes) do
    []
  end

  defp decode_value(vr, bytes) when vr in [:US, :SS, :UL, :SL, :FL, :FD, :AT] do
    decode_numeric(vr, bytes)
  end

  defp decode_value(vr, bytes) when vr in [:OB, :OW, :OD, :OF, :OL, :UN] do
    bytes
  end

  defp decode_value(_vr, bytes) do
    bytes
    |> String.trim_trailing(<<0>>)
    |> String.trim_trailing(" ")
  end

  defp decode_numeric(:US, bytes), do: decode_uint16_list(bytes)
  defp decode_numeric(:SS, bytes), do: decode_int16_list(bytes)
  defp decode_numeric(:UL, bytes), do: decode_uint32_list(bytes)
  defp decode_numeric(:SL, bytes), do: decode_int32_list(bytes)
  defp decode_numeric(:FL, bytes), do: decode_float32_list(bytes)
  defp decode_numeric(:FD, bytes), do: decode_float64_list(bytes)
  defp decode_numeric(:AT, bytes), do: decode_tag_list(bytes)

  defp decode_uint16_list(bytes, acc \\ [])
  defp decode_uint16_list(<<>>, acc), do: unwrap_single(Enum.reverse(acc))
  defp decode_uint16_list(<<val::16-little, rest::binary>>, acc),
    do: decode_uint16_list(rest, [val | acc])

  defp decode_int16_list(bytes, acc \\ [])
  defp decode_int16_list(<<>>, acc), do: unwrap_single(Enum.reverse(acc))
  defp decode_int16_list(<<val::16-signed-little, rest::binary>>, acc),
    do: decode_int16_list(rest, [val | acc])

  defp decode_uint32_list(bytes, acc \\ [])
  defp decode_uint32_list(<<>>, acc), do: unwrap_single(Enum.reverse(acc))
  defp decode_uint32_list(<<val::32-little, rest::binary>>, acc),
    do: decode_uint32_list(rest, [val | acc])

  defp decode_int32_list(bytes, acc \\ [])
  defp decode_int32_list(<<>>, acc), do: unwrap_single(Enum.reverse(acc))
  defp decode_int32_list(<<val::32-signed-little, rest::binary>>, acc),
    do: decode_int32_list(rest, [val | acc])

  defp decode_float32_list(bytes, acc \\ [])
  defp decode_float32_list(<<>>, acc), do: unwrap_single(Enum.reverse(acc))
  defp decode_float32_list(<<val::32-float-little, rest::binary>>, acc),
    do: decode_float32_list(rest, [val | acc])

  defp decode_float64_list(bytes, acc \\ [])
  defp decode_float64_list(<<>>, acc), do: unwrap_single(Enum.reverse(acc))
  defp decode_float64_list(<<val::64-float-little, rest::binary>>, acc),
    do: decode_float64_list(rest, [val | acc])

  defp decode_tag_list(bytes, acc \\ [])
  defp decode_tag_list(<<>>, acc), do: unwrap_single(Enum.reverse(acc))
  defp decode_tag_list(<<g::16-little, e::16-little, rest::binary>>, acc),
    do: decode_tag_list(rest, [{g, e} | acc])

  defp unwrap_single([single]), do: single
  defp unwrap_single(list), do: list
end
