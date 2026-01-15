defmodule Dcmix.Writer.ExplicitVR do
  @moduledoc """
  Encoder for Explicit VR transfer syntaxes.
  """

  alias Dcmix.{Tag, VR, DataElement, DataSet}

  @undefined_length 0xFFFFFFFF

  @doc """
  Encodes data elements to binary using Explicit VR encoding.

  ## Options
  - `:big_endian` - Use big-endian byte ordering (default: false)
  """
  @spec encode(DataSet.t(), keyword()) :: binary()
  def encode(%DataSet{} = dataset, opts \\ []) do
    big_endian = Keyword.get(opts, :big_endian, false)

    dataset
    |> DataSet.to_list()
    |> Enum.map(&encode_element(&1, big_endian))
    |> IO.iodata_to_binary()
  end

  @doc """
  Encodes a single data element.
  """
  @spec encode_element(DataElement.t(), boolean()) :: iodata()
  def encode_element(%DataElement{tag: tag, vr: vr, value: value}, big_endian) do
    tag_bytes = encode_tag(tag, big_endian)

    cond do
      # Item delimiters have no VR
      Tag.item_tag?(tag) ->
        [tag_bytes, encode_uint32(0, big_endian)]

      vr == :SQ ->
        encode_sequence(tag, vr, value, big_endian)

      true ->
        value_bytes = encode_value(vr, value, big_endian)
        length = byte_size(value_bytes)

        if VR.long_length?(vr) do
          [
            tag_bytes,
            Atom.to_string(vr),
            <<0::16>>,
            encode_uint32(length, big_endian),
            value_bytes
          ]
        else
          [
            tag_bytes,
            Atom.to_string(vr),
            encode_uint16(length, big_endian),
            value_bytes
          ]
        end
    end
  end

  defp encode_sequence(tag, vr, items, big_endian) when is_list(items) do
    tag_bytes = encode_tag(tag, big_endian)
    vr_bytes = Atom.to_string(vr)

    items_bytes =
      items
      |> Enum.map(&encode_item(&1, big_endian))
      |> IO.iodata_to_binary()

    # Use undefined length for sequences
    [
      tag_bytes,
      vr_bytes,
      <<0::16>>,
      encode_uint32(@undefined_length, big_endian),
      items_bytes,
      # Sequence Delimitation Item
      encode_tag({0xFFFE, 0xE0DD}, big_endian),
      encode_uint32(0, big_endian)
    ]
  end

  defp encode_sequence(tag, vr, _value, big_endian) do
    # Empty sequence
    encode_sequence(tag, vr, [], big_endian)
  end

  defp encode_item(%DataSet{} = item_dataset, big_endian) do
    item_bytes = encode(item_dataset, big_endian: big_endian)

    [
      # Item tag
      encode_tag({0xFFFE, 0xE000}, big_endian),
      encode_uint32(byte_size(item_bytes), big_endian),
      item_bytes
    ]
  end

  defp encode_tag({group, element}, big_endian) do
    if big_endian do
      <<group::16-big, element::16-big>>
    else
      <<group::16-little, element::16-little>>
    end
  end

  defp encode_value(vr, value, big_endian) when vr in [:US, :SS, :UL, :SL, :FL, :FD, :AT] do
    encode_numeric(vr, value, big_endian)
  end

  defp encode_value(vr, value, _big_endian) when vr in [:OB, :OW, :OD, :OF, :OL, :UN] do
    # Binary data - return as-is (with padding if needed)
    cond do
      is_binary(value) -> pad_binary(value, vr)
      is_list(value) -> IO.iodata_to_binary(value)
      true -> <<>>
    end
  end

  defp encode_value(vr, value, _big_endian) do
    # String types
    string_value =
      cond do
        is_binary(value) -> value
        is_list(value) -> Enum.join(value, "\\")
        is_nil(value) -> ""
        true -> to_string(value)
      end

    pad_string(string_value, vr)
  end

  defp encode_numeric(:US, value, big_endian), do: encode_uint16_values(value, big_endian)
  defp encode_numeric(:SS, value, big_endian), do: encode_int16_values(value, big_endian)
  defp encode_numeric(:UL, value, big_endian), do: encode_uint32_values(value, big_endian)
  defp encode_numeric(:SL, value, big_endian), do: encode_int32_values(value, big_endian)
  defp encode_numeric(:FL, value, big_endian), do: encode_float32_values(value, big_endian)
  defp encode_numeric(:FD, value, big_endian), do: encode_float64_values(value, big_endian)
  defp encode_numeric(:AT, value, big_endian), do: encode_tag_values(value, big_endian)

  defp encode_uint16_values(value, big_endian) when is_integer(value) do
    encode_uint16(value, big_endian)
  end

  defp encode_uint16_values(values, big_endian) when is_list(values) do
    values |> Enum.map(&encode_uint16(&1, big_endian)) |> IO.iodata_to_binary()
  end

  defp encode_int16_values(value, big_endian) when is_integer(value) do
    if big_endian, do: <<value::16-signed-big>>, else: <<value::16-signed-little>>
  end

  defp encode_int16_values(values, big_endian) when is_list(values) do
    values |> Enum.map(&encode_int16_values(&1, big_endian)) |> IO.iodata_to_binary()
  end

  defp encode_uint32_values(value, big_endian) when is_integer(value) do
    encode_uint32(value, big_endian)
  end

  defp encode_uint32_values(values, big_endian) when is_list(values) do
    values |> Enum.map(&encode_uint32(&1, big_endian)) |> IO.iodata_to_binary()
  end

  defp encode_int32_values(value, big_endian) when is_integer(value) do
    if big_endian, do: <<value::32-signed-big>>, else: <<value::32-signed-little>>
  end

  defp encode_int32_values(values, big_endian) when is_list(values) do
    values |> Enum.map(&encode_int32_values(&1, big_endian)) |> IO.iodata_to_binary()
  end

  defp encode_float32_values(value, big_endian) when is_float(value) do
    if big_endian, do: <<value::32-float-big>>, else: <<value::32-float-little>>
  end

  defp encode_float32_values(values, big_endian) when is_list(values) do
    values |> Enum.map(&encode_float32_values(&1, big_endian)) |> IO.iodata_to_binary()
  end

  defp encode_float64_values(value, big_endian) when is_float(value) do
    if big_endian, do: <<value::64-float-big>>, else: <<value::64-float-little>>
  end

  defp encode_float64_values(values, big_endian) when is_list(values) do
    values |> Enum.map(&encode_float64_values(&1, big_endian)) |> IO.iodata_to_binary()
  end

  defp encode_tag_values({group, element}, big_endian) do
    encode_tag({group, element}, big_endian)
  end

  defp encode_tag_values(values, big_endian) when is_list(values) do
    values |> Enum.map(&encode_tag_values(&1, big_endian)) |> IO.iodata_to_binary()
  end

  defp encode_uint16(value, true), do: <<value::16-big>>
  defp encode_uint16(value, false), do: <<value::16-little>>

  defp encode_uint32(value, true), do: <<value::32-big>>
  defp encode_uint32(value, false), do: <<value::32-little>>

  defp pad_string(string, vr) do
    padding = VR.padding(vr) || 0x20
    len = byte_size(string)

    if rem(len, 2) == 1 do
      string <> <<padding>>
    else
      string
    end
  end

  defp pad_binary(binary, _vr) do
    len = byte_size(binary)

    if rem(len, 2) == 1 do
      binary <> <<0>>
    else
      binary
    end
  end
end
