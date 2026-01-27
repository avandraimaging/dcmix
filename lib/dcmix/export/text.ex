defmodule Dcmix.Export.Text do
  @moduledoc """
  Exports DICOM DataSet to human-readable text format.

  Produces output similar to dcmdump from DCMTK.
  """

  alias Dcmix.{Tag, DataSet, DataElement, Dictionary}

  @max_value_length 64

  @doc """
  Encodes a DataSet to a human-readable string.

  ## Options
  - `:max_value_length` - Maximum length for value display (default: 64)
  - `:show_length` - Show element length (default: true)
  """
  @spec encode(DataSet.t(), keyword()) :: String.t()
  def encode(%DataSet{} = dataset, opts \\ []) do
    max_length = Keyword.get(opts, :max_value_length, @max_value_length)
    show_length = Keyword.get(opts, :show_length, true)

    dataset
    |> DataSet.to_list()
    |> Enum.map(&format_element(&1, 0, max_length, show_length))
    |> Enum.join("\n")
  end

  defp format_element(%DataElement{tag: tag, vr: vr, value: value, length: length}, indent, max_length, show_length) do
    indent_str = String.duplicate("  ", indent)
    tag_str = Tag.to_string(tag)
    vr_str = if vr, do: Atom.to_string(vr), else: "??"
    keyword = Dictionary.keyword(tag) || "UnknownTag"

    value_str = format_value(vr, value, max_length)
    length_str = if show_length, do: format_length(length), else: ""

    if vr == :SQ and is_list(value) do
      # Sequence with items
      header = "#{indent_str}#{tag_str} #{vr_str} #{keyword}#{length_str}"

      if Enum.empty?(value) do
        header <> " (no items)"
      else
        items_str =
          value
          |> Enum.with_index()
          |> Enum.map(fn {item, idx} ->
            item_header = "#{indent_str}  (Item ##{idx})"
            item_content = format_item(item, indent + 2, max_length, show_length)
            "#{item_header}\n#{item_content}"
          end)
          |> Enum.join("\n")

        "#{header}\n#{items_str}"
      end
    else
      "#{indent_str}#{tag_str} #{vr_str} #{keyword}#{length_str} [#{value_str}]"
    end
  end

  defp format_item(%DataSet{} = item, indent, max_length, show_length) do
    item
    |> DataSet.to_list()
    |> Enum.map(&format_element(&1, indent, max_length, show_length))
    |> Enum.join("\n")
  end

  defp format_length(:undefined), do: " (undefined length)"
  defp format_length(length), do: " ##{length}"

  # format_value clauses - all grouped together
  defp format_value(nil, _, _), do: ""
  defp format_value(_vr, nil, _), do: ""

  defp format_value(:SQ, items, _max_length) when is_list(items) do
    "#{length(items)} item(s)"
  end

  defp format_value(vr, value, _max_length) when vr in [:OB, :OW, :OD, :OF, :OL, :UN] do
    # Binary data - show length and hex preview
    # But handle case where UN is actually a sequence (list of DataSets)
    cond do
      is_binary(value) ->
        format_binary_preview(value)

      is_list(value) and length(value) > 0 and match?(%DataSet{}, hd(value)) ->
        # This is actually a sequence stored with UN VR
        "#{length(value)} item(s)"

      is_list(value) ->
        # Fragments (encapsulated pixel data)
        binary_fragments = Enum.filter(value, &is_binary/1)
        total_size = Enum.reduce(binary_fragments, 0, &(&2 + byte_size(&1)))
        "#{length(binary_fragments)} fragment(s), #{total_size} bytes total"

      true ->
        "(no data)"
    end
  end

  defp format_value(vr, value, max_length) when vr in [:US, :SS, :UL, :SL, :FL, :FD] do
    # Numeric values
    values = if is_list(value), do: value, else: [value]

    values
    |> Enum.map(&format_number/1)
    |> Enum.join(", ")
    |> truncate(max_length)
  end

  defp format_value(:AT, value, max_length) do
    # Attribute Tag
    values = if is_list(value), do: value, else: [value]

    values
    |> Enum.map(fn
      {g, e} -> Tag.to_string({g, e})
      v -> inspect(v)
    end)
    |> Enum.join(", ")
    |> truncate(max_length)
  end

  defp format_value(_vr, value, max_length) when is_binary(value) do
    value
    |> String.trim()
    |> truncate(max_length)
  end

  defp format_value(_vr, value, max_length) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.join("\\")
    |> truncate(max_length)
  end

  defp format_value(_vr, value, max_length) do
    value
    |> to_string()
    |> truncate(max_length)
  end

  # Helper functions
  defp format_binary_preview(binary_data) do
    len = byte_size(binary_data)

    if len == 0 do
      "(no data)"
    else
      preview_bytes = min(16, len)
      preview = binary_part(binary_data, 0, preview_bytes)
      hex = preview |> :binary.bin_to_list() |> Enum.map(&hex_byte/1) |> Enum.join(" ")

      if len > preview_bytes do
        "#{hex}... (#{len} bytes)"
      else
        "#{hex} (#{len} bytes)"
      end
    end
  end

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 6)
  defp format_number(n), do: to_string(n)

  defp hex_byte(byte) do
    byte
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
  end

  defp truncate(string, max_length) when byte_size(string) <= max_length, do: string

  defp truncate(string, max_length) do
    String.slice(string, 0, max_length - 3) <> "..."
  end
end
