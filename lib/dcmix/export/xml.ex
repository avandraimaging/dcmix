defmodule Dcmix.Export.XML do
  @moduledoc """
  Exports DICOM DataSet to XML format.

  Follows the Native DICOM Model defined in PS3.19.
  """

  alias Dcmix.{Tag, DataSet, DataElement, Dictionary}

  @doc """
  Encodes a DataSet to XML string.

  ## Options
  - `:pretty` - Pretty-print XML with indentation (default: true)
  """
  @spec encode(DataSet.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def encode(%DataSet{} = dataset, opts \\ []) do
    pretty = Keyword.get(opts, :pretty, true)

    elements_xml = encode_elements(dataset, if(pretty, do: 1, else: 0), pretty)

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <NativeDicomModel xmlns="http://dicom.nema.org/PS3.19/models/NativeDICOM">
    #{elements_xml}
    </NativeDicomModel>
    """

    {:ok, String.trim(xml)}
  end

  defp encode_elements(%DataSet{} = dataset, indent_level, pretty) do
    dataset
    |> DataSet.to_list()
    |> Enum.reject(fn e -> Tag.item_tag?(e.tag) end)
    |> Enum.map(&encode_element(&1, indent_level, pretty))
    |> join_elements(pretty)
  end

  defp encode_element(%DataElement{tag: tag, vr: vr, value: value}, indent_level, pretty) do
    indent = if pretty, do: String.duplicate("  ", indent_level), else: ""
    tag_str = tag_to_attr(tag)
    vr_str = if vr, do: Atom.to_string(vr), else: "UN"
    keyword = Dictionary.keyword(tag) || ""

    cond do
      vr == :SQ and is_list(value) ->
        encode_sequence(tag_str, vr_str, keyword, value, indent_level, pretty)

      vr in [:OB, :OD, :OF, :OL, :OW, :UN] ->
        encode_binary_element(tag_str, vr_str, keyword, value, indent, pretty)

      true ->
        encode_value_element(tag_str, vr_str, keyword, vr, value, indent, pretty)
    end
  end

  defp tag_to_attr({group, element}) do
    group_hex = group |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()
    element_hex = element |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()
    "#{group_hex}#{element_hex}"
  end

  defp encode_sequence(tag_str, vr_str, keyword, items, indent_level, pretty) do
    indent = if pretty, do: String.duplicate("  ", indent_level), else: ""
    newline = if pretty, do: "\n", else: ""

    if Enum.empty?(items) do
      "#{indent}<DicomAttribute tag=\"#{tag_str}\" vr=\"#{vr_str}\" keyword=\"#{keyword}\"/>"
    else
      items_xml =
        items
        |> Enum.with_index()
        |> Enum.map(fn {item, idx} ->
          item_indent = if pretty, do: String.duplicate("  ", indent_level + 1), else: ""
          item_content = encode_elements(item, indent_level + 2, pretty)

          if item_content == "" do
            "#{item_indent}<Item number=\"#{idx + 1}\"/>"
          else
            "#{item_indent}<Item number=\"#{idx + 1}\">#{newline}#{item_content}#{newline}#{item_indent}</Item>"
          end
        end)
        |> join_elements(pretty)

      "#{indent}<DicomAttribute tag=\"#{tag_str}\" vr=\"#{vr_str}\" keyword=\"#{keyword}\">#{newline}#{items_xml}#{newline}#{indent}</DicomAttribute>"
    end
  end

  defp encode_binary_element(tag_str, vr_str, keyword, value, indent, pretty) do
    binary_data =
      cond do
        is_binary(value) -> value
        is_list(value) -> IO.iodata_to_binary(value)
        true -> <<>>
      end

    if byte_size(binary_data) == 0 do
      "#{indent}<DicomAttribute tag=\"#{tag_str}\" vr=\"#{vr_str}\" keyword=\"#{keyword}\"/>"
    else
      base64 = Base.encode64(binary_data)
      newline = if pretty, do: "\n", else: ""
      inner_indent = if pretty, do: indent <> "  ", else: ""

      "#{indent}<DicomAttribute tag=\"#{tag_str}\" vr=\"#{vr_str}\" keyword=\"#{keyword}\">#{newline}#{inner_indent}<InlineBinary>#{base64}</InlineBinary>#{newline}#{indent}</DicomAttribute>"
    end
  end

  defp encode_value_element(tag_str, vr_str, keyword, vr, value, indent, pretty) do
    values = normalize_values(vr, value)

    if Enum.empty?(values) do
      "#{indent}<DicomAttribute tag=\"#{tag_str}\" vr=\"#{vr_str}\" keyword=\"#{keyword}\"/>"
    else
      newline = if pretty, do: "\n", else: ""
      inner_indent = if pretty, do: indent <> "  ", else: ""

      values_xml =
        values
        |> Enum.with_index(1)
        |> Enum.map(fn {val, num} ->
          escaped_val = escape_xml(val)

          if vr == :PN do
            "#{inner_indent}<PersonName number=\"#{num}\"><Alphabetic><FamilyName>#{escaped_val}</FamilyName></Alphabetic></PersonName>"
          else
            "#{inner_indent}<Value number=\"#{num}\">#{escaped_val}</Value>"
          end
        end)
        |> join_elements(pretty)

      "#{indent}<DicomAttribute tag=\"#{tag_str}\" vr=\"#{vr_str}\" keyword=\"#{keyword}\">#{newline}#{values_xml}#{newline}#{indent}</DicomAttribute>"
    end
  end

  defp normalize_values(_vr, nil), do: []
  defp normalize_values(_vr, ""), do: []

  defp normalize_values(vr, value) when vr in [:AT] do
    values = if is_list(value), do: value, else: [value]

    Enum.map(values, fn
      {g, e} ->
        g_hex = g |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()
        e_hex = e |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()
        "#{g_hex}#{e_hex}"

      v ->
        to_string(v)
    end)
  end

  defp normalize_values(_vr, value) when is_list(value) do
    Enum.map(value, &to_string/1)
  end

  defp normalize_values(_vr, value) when is_binary(value) do
    if String.contains?(value, "\\") do
      String.split(value, "\\")
    else
      [value]
    end
  end

  defp normalize_values(_vr, value), do: [to_string(value)]

  defp escape_xml(string) when is_binary(string) do
    string
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape_xml(value), do: escape_xml(to_string(value))

  defp join_elements(elements, true), do: Enum.join(elements, "\n")
  defp join_elements(elements, false), do: Enum.join(elements, "")
end
