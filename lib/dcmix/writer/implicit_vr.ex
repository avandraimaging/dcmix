defmodule Dcmix.Writer.ImplicitVR do
  @moduledoc """
  Encoder for Implicit VR Little Endian transfer syntax.
  """

  alias Dcmix.{Tag, VR, DataElement, DataSet}

  @undefined_length 0xFFFFFFFF

  @doc """
  Encodes data elements to binary using Implicit VR Little Endian encoding.
  """
  @spec encode(DataSet.t()) :: binary()
  def encode(%DataSet{} = dataset) do
    dataset
    |> DataSet.to_list()
    |> Enum.map(&encode_element/1)
    |> IO.iodata_to_binary()
  end

  @doc """
  Encodes a single data element.
  """
  @spec encode_element(DataElement.t()) :: iodata()
  def encode_element(%DataElement{tag: tag, vr: vr, value: value}) do
    tag_bytes = encode_tag(tag)

    cond do
      # Item delimiters
      Tag.item_tag?(tag) ->
        [tag_bytes, <<0::32-little>>]

      vr == :SQ ->
        encode_sequence(tag, value)

      true ->
        value_bytes = encode_value(vr, value)
        length = byte_size(value_bytes)

        [
          tag_bytes,
          <<length::32-little>>,
          value_bytes
        ]
    end
  end

  defp encode_sequence(tag, items) when is_list(items) do
    tag_bytes = encode_tag(tag)

    items_bytes =
      items
      |> Enum.map(&encode_item/1)
      |> IO.iodata_to_binary()

    [
      tag_bytes,
      <<@undefined_length::32-little>>,
      items_bytes,
      # Sequence Delimitation Item
      encode_tag({0xFFFE, 0xE0DD}),
      <<0::32-little>>
    ]
  end

  defp encode_sequence(tag, _value) do
    encode_sequence(tag, [])
  end

  defp encode_item(%DataSet{} = item_dataset) do
    item_bytes = encode(item_dataset)

    [
      encode_tag({0xFFFE, 0xE000}),
      <<byte_size(item_bytes)::32-little>>,
      item_bytes
    ]
  end

  defp encode_tag({group, element}) do
    <<group::16-little, element::16-little>>
  end

  defp encode_value(vr, value) when vr in [:US, :SS, :UL, :SL, :FL, :FD, :AT] do
    encode_numeric(vr, value)
  end

  defp encode_value(vr, value) when vr in [:OB, :OW, :OD, :OF, :OL, :UN] do
    cond do
      is_binary(value) -> pad_binary(value)
      is_list(value) -> IO.iodata_to_binary(value)
      true -> <<>>
    end
  end

  defp encode_value(vr, value) do
    string_value =
      cond do
        is_binary(value) -> value
        is_list(value) -> Enum.join(value, "\\")
        is_nil(value) -> ""
        true -> to_string(value)
      end

    pad_string(string_value, vr)
  end

  defp encode_numeric(:US, value), do: encode_uint16_values(value)
  defp encode_numeric(:SS, value), do: encode_int16_values(value)
  defp encode_numeric(:UL, value), do: encode_uint32_values(value)
  defp encode_numeric(:SL, value), do: encode_int32_values(value)
  defp encode_numeric(:FL, value), do: encode_float32_values(value)
  defp encode_numeric(:FD, value), do: encode_float64_values(value)
  defp encode_numeric(:AT, value), do: encode_tag_values(value)

  defp encode_uint16_values(value) when is_integer(value), do: <<value::16-little>>

  defp encode_uint16_values(values) when is_list(values) do
    values |> Enum.map(&<<&1::16-little>>) |> IO.iodata_to_binary()
  end

  defp encode_int16_values(value) when is_integer(value), do: <<value::16-signed-little>>

  defp encode_int16_values(values) when is_list(values) do
    values |> Enum.map(&<<&1::16-signed-little>>) |> IO.iodata_to_binary()
  end

  defp encode_uint32_values(value) when is_integer(value), do: <<value::32-little>>

  defp encode_uint32_values(values) when is_list(values) do
    values |> Enum.map(&<<&1::32-little>>) |> IO.iodata_to_binary()
  end

  defp encode_int32_values(value) when is_integer(value), do: <<value::32-signed-little>>

  defp encode_int32_values(values) when is_list(values) do
    values |> Enum.map(&<<&1::32-signed-little>>) |> IO.iodata_to_binary()
  end

  defp encode_float32_values(value) when is_float(value), do: <<value::32-float-little>>

  defp encode_float32_values(values) when is_list(values) do
    values |> Enum.map(&<<&1::32-float-little>>) |> IO.iodata_to_binary()
  end

  defp encode_float64_values(value) when is_float(value), do: <<value::64-float-little>>

  defp encode_float64_values(values) when is_list(values) do
    values |> Enum.map(&<<&1::64-float-little>>) |> IO.iodata_to_binary()
  end

  defp encode_tag_values({group, element}), do: encode_tag({group, element})

  defp encode_tag_values(values) when is_list(values) do
    values |> Enum.map(&encode_tag/1) |> IO.iodata_to_binary()
  end

  defp pad_string(string, vr) do
    padding = VR.padding(vr) || 0x20
    len = byte_size(string)

    if rem(len, 2) == 1 do
      string <> <<padding>>
    else
      string
    end
  end

  defp pad_binary(binary) do
    len = byte_size(binary)

    if rem(len, 2) == 1 do
      binary <> <<0>>
    else
      binary
    end
  end
end
