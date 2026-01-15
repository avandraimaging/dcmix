defmodule Dcmix.Export.JSON do
  @moduledoc """
  Exports DICOM DataSet to JSON format.

  Follows the DICOM JSON Model defined in PS3.18 F.2.
  """

  alias Dcmix.{Tag, DataSet, DataElement}

  @doc """
  Encodes a DataSet to JSON string.

  ## Options
  - `:pretty` - Pretty-print JSON (default: false)
  """
  @spec encode(DataSet.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def encode(%DataSet{} = dataset, opts \\ []) do
    pretty = Keyword.get(opts, :pretty, false)
    map = dataset_to_map(dataset)

    json_opts = if pretty, do: [pretty: true], else: []

    case Jason.encode(map, json_opts) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_encode_error, reason}}
    end
  end

  @doc """
  Converts a DataSet to a map following DICOM JSON Model.
  """
  @spec dataset_to_map(DataSet.t()) :: map()
  def dataset_to_map(%DataSet{} = dataset) do
    dataset
    |> DataSet.to_list()
    |> Enum.reject(fn e -> Tag.item_tag?(e.tag) end)
    |> Enum.map(&element_to_entry/1)
    |> Map.new()
  end

  defp element_to_entry(%DataElement{tag: tag, vr: vr, value: value}) do
    tag_string = tag_to_string(tag)
    value_map = build_value_map(vr, value)
    {tag_string, value_map}
  end

  defp tag_to_string({group, element}) do
    group_hex = group |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()

    element_hex =
      element |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()

    "#{group_hex}#{element_hex}"
  end

  defp build_value_map(nil, _value), do: %{}

  defp build_value_map(:SQ, items) when is_list(items) do
    %{
      "vr" => "SQ",
      "Value" => Enum.map(items, &dataset_to_map/1)
    }
  end

  defp build_value_map(:SQ, _), do: %{"vr" => "SQ", "Value" => []}

  defp build_value_map(vr, value) when vr in [:OB, :OD, :OF, :OL, :OW, :UN] do
    # Binary data - encode as Base64 InlineBinary
    # But handle case where UN is actually a sequence (list of DataSets)
    cond do
      is_binary(value) ->
        %{
          "vr" => Atom.to_string(vr),
          "InlineBinary" => Base.encode64(value)
        }

      match?([%DataSet{} | _], value) ->
        # This is actually a sequence stored with UN VR
        %{
          "vr" => "SQ",
          "Value" => Enum.map(value, &dataset_to_map/1)
        }

      is_list(value) ->
        # Fragments (encapsulated pixel data)
        binary_fragments = Enum.filter(value, &is_binary/1)
        binary_data = IO.iodata_to_binary(binary_fragments)

        %{
          "vr" => Atom.to_string(vr),
          "InlineBinary" => Base.encode64(binary_data)
        }

      true ->
        %{"vr" => Atom.to_string(vr)}
    end
  end

  defp build_value_map(vr, nil) do
    %{"vr" => Atom.to_string(vr)}
  end

  defp build_value_map(vr, value) do
    values = normalize_value(vr, value)

    if values == [] do
      %{"vr" => Atom.to_string(vr)}
    else
      %{
        "vr" => Atom.to_string(vr),
        "Value" => values
      }
    end
  end

  defp normalize_value(_vr, nil), do: []
  defp normalize_value(_vr, ""), do: []

  defp normalize_value(vr, value) when vr in [:PN] do
    # Person Name - special handling
    values = to_list(value)

    Enum.map(values, fn name ->
      %{"Alphabetic" => name}
    end)
  end

  defp normalize_value(vr, value) when vr in [:US, :SS, :UL, :SL, :FL, :FD] do
    # Numeric values
    to_list(value)
  end

  defp normalize_value(vr, value) when vr in [:AT] do
    # Attribute Tag - format as string
    values = to_list(value)

    Enum.map(values, fn
      {g, e} ->
        g_hex = g |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()
        e_hex = e |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()
        "#{g_hex}#{e_hex}"

      v when is_binary(v) ->
        v
    end)
  end

  defp normalize_value(vr, value) when vr in [:DS, :IS] do
    # Decimal/Integer String - convert to numbers if possible
    values =
      value
      |> to_list()
      |> Enum.map(&parse_numeric_string/1)

    values
  end

  defp normalize_value(_vr, value) do
    # String values
    to_list(value)
  end

  defp to_list(value) when is_list(value), do: value

  defp to_list(value) when is_binary(value) do
    if String.contains?(value, "\\") do
      String.split(value, "\\")
    else
      [value]
    end
  end

  defp to_list(value), do: [value]

  defp parse_numeric_string(string) when is_binary(string) do
    trimmed = String.trim(string)

    cond do
      trimmed == "" ->
        nil

      String.contains?(trimmed, ".") ->
        case Float.parse(trimmed) do
          {float, ""} -> float
          _ -> trimmed
        end

      true ->
        case Integer.parse(trimmed) do
          {int, ""} -> int
          _ -> trimmed
        end
    end
  end

  defp parse_numeric_string(value), do: value
end
