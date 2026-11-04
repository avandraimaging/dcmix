defmodule Dcmix.Parser.ImplicitVR do
  @moduledoc """
  Parser for Implicit VR Little Endian transfer syntax.

  In Implicit VR encoding, elements don't include the VR in the data.
  The VR must be looked up from the data dictionary. All elements use
  a 4-byte length field, and byte ordering is always little-endian.

  A tag the dictionary gives more than one VR takes the one the elements read
  before it decide, from its own data set or the nearest enclosing one, as
  dcmtk and pydicom decide them:

    * "US or SS" (SmallestImagePixelValue, PixelPaddingValue, LUTDescriptor
      and the like): SS when PixelRepresentation is 1, US otherwise.
    * LUTData, "US or OW": US when its item's LUTDescriptor's first value is
      1, OW otherwise.
    * "OB or OW" (PixelData, OverlayData, WaveformData): OW, as PS3.5 encodes
      them in Implicit VR.

  When nothing decides, the tag takes the dictionary's `vr`; the retired
  GrayLookupTableData ("US or SS or OW") goes by PixelRepresentation too. A LUT descriptor's
  first and third values are always unsigned. A value whose length doesn't fit
  its VR, or a defined-length sequence whose bytes aren't items, is kept as UN
  with its bytes.
  """

  alias Dcmix.{Tag, DataElement, DataSet, Dictionary}

  @undefined_length 0xFFFFFFFF

  @pixel_representation {0x0028, 0x0103}
  @lut_descriptor {0x0028, 0x3002}
  @lut_data {0x0028, 0x3006}

  # LUTDescriptor and the Red, Green and Blue Palette Color Lookup Table
  # Descriptors: their first and third values are US whatever the VR.
  @lut_descriptors [{0x0028, 0x3002}, {0x0028, 0x1101}, {0x0028, 0x1102}, {0x0028, 0x1103}]

  @value_sizes %{US: 2, SS: 2, UL: 4, SL: 4, FL: 4, AT: 4, FD: 8}

  # What the elements read so far decide for those that follow.
  @no_context %{pixel_representation: nil, lut_entries: nil}

  @doc """
  Parses data elements from binary data using Implicit VR encoding.

  ## Options
  - `:stop_tag` - Stop parsing when this tag is encountered (exclusive)
  """
  @spec parse(binary(), keyword()) :: {:ok, DataSet.t(), binary()} | {:error, term()}
  def parse(data, opts \\ []) do
    stop_tag = Keyword.get(opts, :stop_tag, nil)
    parse_elements(data, [], stop_tag, @no_context)
  end

  defp parse_elements(<<>>, elements, _stop_tag, _context) do
    {:ok, DataSet.new(Enum.reverse(elements)), <<>>}
  end

  defp parse_elements(data, elements, _stop_tag, _context) when byte_size(data) < 8 do
    {:ok, DataSet.new(Enum.reverse(elements)), data}
  end

  defp parse_elements(data, elements, stop_tag, context) do
    with {:ok, tag, rest} <- parse_tag(data),
         :continue <- check_stop_tag(tag, stop_tag),
         {:ok, element, rest} <- parse_element(tag, rest, context) do
      parse_elements(rest, [element | elements], stop_tag, note(context, element))
    else
      :stop -> {:ok, DataSet.new(Enum.reverse(elements)), data}
      {:error, _} = error -> error
    end
  end

  defp check_stop_tag(tag, stop_tag) do
    if stop_tag && Tag.compare(tag, stop_tag) != :lt, do: :stop, else: :continue
  end

  defp parse_tag(<<group::16-little, element::16-little, rest::binary>>) do
    {:ok, {group, element}, rest}
  end

  defp parse_tag(_), do: {:error, :unexpected_eof}

  defp parse_element(tag, data, context) do
    case data do
      <<length::32-little, rest::binary>> ->
        vr = lookup_vr(tag, context)
        read_value(tag, vr, length, rest, context)

      _ ->
        {:error, :unexpected_eof}
    end
  end

  defp note(context, %DataElement{tag: @pixel_representation, value: value})
       when is_integer(value),
       do: %{context | pixel_representation: value}

  defp note(context, %DataElement{tag: @lut_descriptor, value: [entries | _rest]}),
    do: %{context | lut_entries: entries}

  defp note(context, _element), do: context

  defp lookup_vr(tag, context) do
    # Item delimiters don't have VR
    if Tag.item_tag?(tag) do
      nil
    else
      case Dictionary.vrs(tag) do
        [] -> :UN
        [vr] -> vr
        vrs -> decided_vr(tag, vrs, context)
      end
    end
  end

  defp decided_vr(@lut_data, _vrs, %{lut_entries: entries})
       when is_integer(entries) and entries != 1,
       do: :OW

  defp decided_vr(_tag, vrs, %{pixel_representation: 1}) do
    if :SS in vrs, do: :SS, else: hd(vrs)
  end

  defp decided_vr(_tag, vrs, _context), do: hd(vrs)

  defp read_value(tag, vr, @undefined_length, data, context) do
    # Undefined length: a sequence, or a UN holding one
    parse_sequence(tag, vr, data, context)
  end

  defp read_value(tag, vr, length, data, context) when byte_size(data) >= length do
    <<value_bytes::binary-size(^length), rest::binary>> = data

    cond do
      vr == :SQ and length > 0 ->
        case parse_sequence_defined(value_bytes, context) do
          {:ok, items} -> {:ok, DataElement.new(tag, vr, items, length), rest}
          {:error, _} -> {:ok, DataElement.new(tag, :UN, value_bytes, length), rest}
        end

      not fits?(vr, length) ->
        {:ok, DataElement.new(tag, :UN, value_bytes, length), rest}

      true ->
        {:ok, DataElement.new(tag, vr, decode_value(tag, vr, value_bytes), length), rest}
    end
  end

  defp read_value(_tag, _vr, _length, _data, _context) do
    {:error, :unexpected_eof}
  end

  defp fits?(vr, length) do
    case Map.fetch(@value_sizes, vr) do
      {:ok, size} -> rem(length, size) == 0
      :error -> true
    end
  end

  defp parse_sequence(tag, vr, data, context) do
    case parse_sequence_items(data, [], context) do
      {:ok, items, rest} ->
        {:ok, DataElement.new(tag, vr || :SQ, items, :undefined), rest}

      {:error, _} = error ->
        error
    end
  end

  defp parse_sequence_items(data, items, context) do
    with {:ok, tag, rest} <- parse_tag(data) do
      handle_seq_tag(tag, rest, items, context)
    end
  end

  defp handle_seq_tag({0xFFFE, 0xE0DD}, <<_length::32-little, rest::binary>>, items, _context) do
    {:ok, Enum.reverse(items), rest}
  end

  defp handle_seq_tag({0xFFFE, 0xE0DD}, _, _items, _context), do: {:error, :unexpected_eof}

  defp handle_seq_tag({0xFFFE, 0xE000}, <<length::32-little, rest::binary>>, items, context) do
    with {:ok, item_ds, rest} <- parse_item(length, rest, context) do
      parse_sequence_items(rest, [item_ds | items], context)
    end
  end

  defp handle_seq_tag({0xFFFE, 0xE000}, _, _items, _context), do: {:error, :unexpected_eof}

  defp handle_seq_tag(tag, _rest, _items, _context),
    do: {:error, {:unexpected_tag_in_sequence, tag}}

  defp parse_sequence_defined(data, context) do
    parse_sequence_items_defined(data, [], context)
  end

  defp parse_sequence_items_defined(<<>>, items, _context) do
    {:ok, Enum.reverse(items)}
  end

  defp parse_sequence_items_defined(data, items, context) do
    with {:ok, tag, rest} <- parse_tag(data) do
      handle_seq_defined_tag(tag, rest, items, context)
    end
  end

  defp handle_seq_defined_tag(
         {0xFFFE, 0xE000},
         <<length::32-little, rest::binary>>,
         items,
         context
       ) do
    with {:ok, item_ds, rest} <- parse_item(length, rest, context) do
      parse_sequence_items_defined(rest, [item_ds | items], context)
    end
  end

  defp handle_seq_defined_tag({0xFFFE, 0xE000}, _, _items, _context),
    do: {:error, :unexpected_eof}

  defp handle_seq_defined_tag(_tag, _rest, _items, _context), do: {:error, :not_a_sequence}

  # An item starts from its enclosing data set's PixelRepresentation; a LUT's
  # descriptor and data are in the same item.
  defp parse_item(length, data, context),
    do: read_item(length, data, %{context | lut_entries: nil})

  defp read_item(@undefined_length, data, context) do
    parse_item_undefined(data, [], context)
  end

  defp read_item(length, data, context) when byte_size(data) >= length do
    <<item_data::binary-size(^length), rest::binary>> = data

    case parse_elements(item_data, [], nil, context) do
      {:ok, ds, _remaining} -> {:ok, ds, rest}
      {:error, _} = error -> error
    end
  end

  defp read_item(_length, _data, _context) do
    {:error, :unexpected_eof}
  end

  defp parse_item_undefined(data, elements, context) do
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
        case parse_element(tag, rest, context) do
          {:ok, element, rest} ->
            parse_item_undefined(rest, [element | elements], note(context, element))

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp decode_value(_tag, :SQ, _bytes) do
    []
  end

  defp decode_value(tag, :SS, bytes) when tag in @lut_descriptors and byte_size(bytes) == 6 do
    [_first, second, _third] = decode_numeric(:SS, bytes)
    [first, _second, third] = decode_numeric(:US, bytes)
    [first, second, third]
  end

  defp decode_value(_tag, vr, bytes) when vr in [:US, :SS, :UL, :SL, :FL, :FD, :AT] do
    decode_numeric(vr, bytes)
  end

  defp decode_value(_tag, vr, bytes) when vr in [:OB, :OW, :OD, :OF, :OL, :UN] do
    bytes
  end

  defp decode_value(_tag, _vr, bytes) do
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
