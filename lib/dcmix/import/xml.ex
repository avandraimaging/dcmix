defmodule Dcmix.Import.XML do
  @moduledoc """
  Imports DICOM DataSet from XML format.

  Parses the Native DICOM Model defined in PS3.19.
  This is the inverse of `Dcmix.Export.XML`.
  """

  alias Dcmix.{DataSet, DataElement}

  @doc """
  Decodes an XML string to a DataSet.

  ## Options
  - `:template` - An existing DataSet to merge the XML data into

  ## Examples

      {:ok, dataset} = Dcmix.Import.XML.decode(xml_string)
      {:ok, dataset} = Dcmix.Import.XML.decode(xml_string, template: existing_dataset)
  """
  @spec decode(String.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def decode(xml_string, opts \\ []) do
    template = Keyword.get(opts, :template)

    with {:ok, elements} <- parse_xml(xml_string) do
      dataset = DataSet.new(elements)

      if template do
        {:ok, DataSet.merge(template, dataset)}
      else
        {:ok, dataset}
      end
    end
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  @doc """
  Decodes an XML file to a DataSet.
  """
  @spec decode_file(Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def decode_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, content} -> decode(content, opts)
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  defp parse_xml(xml_string) do
    # Simple XML parsing - find all DicomAttribute elements
    elements =
      xml_string
      |> extract_dicom_attributes()
      |> Enum.map(&parse_dicom_attribute/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn %DataElement{tag: tag} -> tag end)

    {:ok, elements}
  end

  defp extract_dicom_attributes(xml) do
    # Find all DicomAttribute elements, handling nested structures
    extract_dicom_attributes_acc(xml, [])
    |> Enum.reverse()
  end

  defp extract_dicom_attributes_acc(xml, acc) do
    # Find the next DicomAttribute opening tag
    case Regex.run(~r/<DicomAttribute\s+([^>]*?)(\/?>)/s, xml, return: :index) do
      nil ->
        acc

      [{start_pos, match_len}, {attr_start, attr_len}, {close_start, close_len}] ->
        attrs_str = binary_part(xml, attr_start, attr_len)
        close_tag = binary_part(xml, close_start, close_len)
        process_dicom_attribute(xml, acc, start_pos, match_len, attrs_str, close_tag)
    end
  end

  defp process_dicom_attribute(xml, acc, start_pos, match_len, attrs_str, "/>") do
    # Self-closing element
    rest = binary_part(xml, start_pos + match_len, byte_size(xml) - start_pos - match_len)
    extract_dicom_attributes_acc(rest, [[attrs_str] | acc])
  end

  defp process_dicom_attribute(xml, acc, start_pos, match_len, attrs_str, _close_tag) do
    # Has content - find the matching closing tag
    content_start = start_pos + match_len
    rest_from_content = binary_part(xml, content_start, byte_size(xml) - content_start)
    process_content_element(rest_from_content, acc, attrs_str)
  end

  defp process_content_element(rest_from_content, acc, attrs_str) do
    case find_closing_tag(rest_from_content, "DicomAttribute", 0, 0) do
      {:ok, content_end} ->
        content = binary_part(rest_from_content, 0, content_end)
        after_close = content_end + byte_size("</DicomAttribute>")
        rest = binary_part(rest_from_content, after_close, byte_size(rest_from_content) - after_close)
        extract_dicom_attributes_acc(rest, [[attrs_str, content] | acc])

      :error ->
        acc
    end
  end

  defp find_closing_tag(xml, tag_name, depth, pos) do
    open_pattern = ~r/<#{tag_name}\s+[^>]*(?<!\/)?>/s
    close_pattern = ~r/<\/#{tag_name}>/s

    open_match = Regex.run(open_pattern, xml, return: :index)
    close_match = Regex.run(close_pattern, xml, return: :index)

    case {open_match, close_match} do
      {_, nil} ->
        :error

      {nil, [{close_pos, _close_len}]} ->
        if depth == 0 do
          {:ok, pos + close_pos}
        else
          rest = binary_part(xml, close_pos + byte_size("</#{tag_name}>"), byte_size(xml) - close_pos - byte_size("</#{tag_name}>"))
          find_closing_tag(rest, tag_name, depth - 1, pos + close_pos + byte_size("</#{tag_name}>"))
        end

      {[{open_pos, open_len}], [{close_pos, _close_len}]} when open_pos < close_pos ->
        # Found another opening tag before the closing tag - increase depth
        rest = binary_part(xml, open_pos + open_len, byte_size(xml) - open_pos - open_len)
        find_closing_tag(rest, tag_name, depth + 1, pos + open_pos + open_len)

      {_, [{close_pos, _close_len}]} ->
        if depth == 0 do
          {:ok, pos + close_pos}
        else
          rest = binary_part(xml, close_pos + byte_size("</#{tag_name}>"), byte_size(xml) - close_pos - byte_size("</#{tag_name}>"))
          find_closing_tag(rest, tag_name, depth - 1, pos + close_pos + byte_size("</#{tag_name}>"))
        end
    end
  end

  defp parse_dicom_attribute([attrs_str]) do
    # Self-closing element (no value)
    parse_dicom_attribute([attrs_str, ""])
  end

  defp parse_dicom_attribute([attrs_str, content]) do
    with {:ok, tag} <- extract_attribute(attrs_str, "tag"),
         {:ok, vr} <- extract_attribute(attrs_str, "vr"),
         {:ok, parsed_tag} <- parse_tag(tag),
         {:ok, parsed_vr} <- parse_vr(vr) do
      value = parse_content(parsed_vr, content)
      DataElement.new(parsed_tag, parsed_vr, value)
    else
      _ -> nil
    end
  end

  defp extract_attribute(attrs_str, name) do
    regex = ~r/#{name}="([^"]*)"/
    case Regex.run(regex, attrs_str) do
      [_, value] -> {:ok, value}
      _ -> {:error, :not_found}
    end
  end

  defp parse_tag(tag_string) when byte_size(tag_string) == 8 do
    with {group, ""} <- Integer.parse(String.slice(tag_string, 0, 4), 16),
         {element, ""} <- Integer.parse(String.slice(tag_string, 4, 4), 16) do
      {:ok, {group, element}}
    else
      _ -> {:error, {:invalid_tag, tag_string}}
    end
  end

  defp parse_tag(tag_string), do: {:error, {:invalid_tag, tag_string}}

  defp parse_vr(vr_string) when is_binary(vr_string) do
    case Dcmix.VR.parse(vr_string) do
      {:ok, vr} -> {:ok, vr}
      {:error, _} -> {:ok, String.to_atom(vr_string)}
    end
  end

  defp parse_content(:SQ, content) do
    # Parse sequence items
    items = extract_sequence_items(content)

    Enum.map(items, fn item_content ->
      attrs = extract_dicom_attributes(item_content)
      elements =
        attrs
        |> Enum.map(&parse_dicom_attribute/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(fn %DataElement{tag: tag} -> tag end)

      DataSet.new(elements)
    end)
  end

  defp parse_content(vr, content) when vr in [:OB, :OD, :OF, :OL, :OW, :UN] do
    # Binary data - look for InlineBinary
    case extract_inline_binary(content) do
      {:ok, base64} ->
        case Base.decode64(base64) do
          {:ok, binary} -> binary
          :error -> nil
        end

      :error ->
        nil
    end
  end

  defp parse_content(:PN, content) do
    # Person Name - extract from PersonName elements
    names = extract_person_names(content)
    join_values(names)
  end

  defp parse_content(:AT, content) do
    # Attribute Tag values
    values = extract_values(content)

    tags =
      Enum.map(values, fn tag_string ->
        case parse_tag(String.trim(tag_string)) do
          {:ok, tag} -> tag
          _ -> tag_string
        end
      end)

    simplify_values(tags)
  end

  defp parse_content(vr, content) when vr in [:US, :SS, :UL, :SL] do
    # Integer values
    values =
      content
      |> extract_values()
      |> Enum.map(fn str ->
        case Integer.parse(String.trim(str)) do
          {int, _} -> int
          :error -> str
        end
      end)

    simplify_values(values)
  end

  defp parse_content(vr, content) when vr in [:FL, :FD] do
    # Float values
    values =
      content
      |> extract_values()
      |> Enum.map(&parse_float_value/1)

    simplify_values(values)
  end

  defp parse_content(_vr, content) do
    # String values
    values =
      content
      |> extract_values()
      |> Enum.map(&unescape_xml/1)

    join_values(values)
  end

  defp parse_float_value(str) do
    trimmed = String.trim(str)

    case Float.parse(trimmed) do
      {float, _} -> float
      :error -> parse_int_as_float(trimmed)
    end
  end

  defp parse_int_as_float(str) do
    case Integer.parse(str) do
      {int, _} -> int * 1.0
      :error -> str
    end
  end

  defp extract_sequence_items(content) do
    # Match Item elements
    regex = ~r/<Item[^>]*>(.*?)<\/Item>/s
    Regex.scan(regex, content, capture: :all_but_first)
    |> Enum.map(fn [item_content] -> item_content end)
  end

  defp extract_inline_binary(content) do
    regex = ~r/<InlineBinary>([^<]*)<\/InlineBinary>/s
    case Regex.run(regex, content) do
      [_, base64] -> {:ok, String.trim(base64)}
      _ -> :error
    end
  end

  defp extract_values(content) do
    regex = ~r/<Value[^>]*>([^<]*)<\/Value>/s
    Regex.scan(regex, content, capture: :all_but_first)
    |> Enum.map(fn [value] -> value end)
  end

  defp extract_person_names(content) do
    # Look for PersonName elements with Alphabetic/FamilyName structure
    regex = ~r/<PersonName[^>]*>(.*?)<\/PersonName>/s
    person_names = Regex.scan(regex, content, capture: :all_but_first)

    Enum.map(person_names, fn [pn_content] ->
      # Try to extract structured name
      family = extract_name_component(pn_content, "FamilyName")
      given = extract_name_component(pn_content, "GivenName")
      middle = extract_name_component(pn_content, "MiddleName")
      prefix = extract_name_component(pn_content, "NamePrefix")
      suffix = extract_name_component(pn_content, "NameSuffix")

      [family, given, middle, prefix, suffix]
      |> Enum.join("^")
      |> String.trim_trailing("^")
    end)
  end

  defp extract_name_component(content, component_name) do
    regex = ~r/<#{component_name}>([^<]*)<\/#{component_name}>/s
    case Regex.run(regex, content) do
      [_, value] -> unescape_xml(value)
      _ -> ""
    end
  end

  defp unescape_xml(string) do
    string
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end

  defp join_values([]), do: nil
  defp join_values([single]), do: single
  defp join_values(values), do: Enum.join(values, "\\")

  defp simplify_values([]), do: nil
  defp simplify_values([single]), do: single
  defp simplify_values(values), do: values
end
