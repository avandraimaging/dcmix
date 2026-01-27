defmodule Dcmix.Import.JSON do
  @moduledoc """
  Imports DICOM DataSet from JSON format.

  Parses the DICOM JSON Model defined in PS3.18 F.2.
  This is the inverse of `Dcmix.Export.JSON`.
  """

  alias Dcmix.{DataSet, DataElement}

  @doc """
  Decodes a JSON string to a DataSet.

  ## Options
  - `:template` - An existing DataSet to merge the JSON data into (like dcm4che's -i option)

  ## Examples

      {:ok, dataset} = Dcmix.Import.JSON.decode(json_string)
      {:ok, dataset} = Dcmix.Import.JSON.decode(json_string, template: existing_dataset)
  """
  @spec decode(String.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def decode(json_string, opts \\ []) do
    template = Keyword.get(opts, :template)

    with {:ok, map} <- Jason.decode(json_string),
         {:ok, dataset} <- map_to_dataset(map) do
      if template do
        {:ok, DataSet.merge(template, dataset)}
      else
        {:ok, dataset}
      end
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:json_decode_error, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Decodes a JSON file to a DataSet.
  """
  @spec decode_file(Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def decode_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, content} -> decode(content, opts)
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  @doc """
  Converts a map (parsed JSON) to a DataSet.
  """
  @spec map_to_dataset(map()) :: {:ok, DataSet.t()} | {:error, term()}
  def map_to_dataset(map) when is_map(map) do
    elements =
      map
      |> Enum.map(&parse_entry/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn %DataElement{tag: tag} -> tag end)

    {:ok, DataSet.new(elements)}
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  defp parse_entry({tag_string, value_map}) when is_binary(tag_string) and is_map(value_map) do
    with {:ok, tag} <- parse_tag(tag_string),
         {:ok, vr} <- parse_vr(value_map),
         {:ok, value} <- parse_value(vr, value_map) do
      DataElement.new(tag, vr, value)
    else
      {:error, _reason} -> nil
    end
  end

  defp parse_entry(_), do: nil

  defp parse_tag(tag_string) when byte_size(tag_string) == 8 do
    with {group, ""} <- Integer.parse(String.slice(tag_string, 0, 4), 16),
         {element, ""} <- Integer.parse(String.slice(tag_string, 4, 4), 16) do
      {:ok, {group, element}}
    else
      _ -> {:error, {:invalid_tag, tag_string}}
    end
  end

  defp parse_tag(tag_string), do: {:error, {:invalid_tag, tag_string}}

  defp parse_vr(%{"vr" => vr_string}) when is_binary(vr_string) do
    case Dcmix.VR.parse(vr_string) do
      {:ok, vr} -> {:ok, vr}
      {:error, _} -> {:ok, String.to_atom(vr_string)}
    end
  end

  defp parse_vr(_), do: {:ok, nil}

  defp parse_value(:SQ, %{"Value" => items}) when is_list(items) do
    datasets =
      Enum.map(items, fn item ->
        case map_to_dataset(item) do
          {:ok, ds} -> ds
          _ -> DataSet.new()
        end
      end)

    {:ok, datasets}
  end

  defp parse_value(:SQ, _), do: {:ok, []}

  defp parse_value(vr, %{"InlineBinary" => base64}) when is_binary(base64) do
    case Base.decode64(base64) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, {:invalid_base64, vr}}
    end
  end

  defp parse_value(vr, %{"Value" => values}) when vr in [:PN] and is_list(values) do
    # Person Name - extract from Alphabetic/Ideographic/Phonetic
    names =
      Enum.map(values, fn
        %{"Alphabetic" => name} when is_binary(name) -> name
        %{"Alphabetic" => name} when is_map(name) -> format_person_name_components(name)
        name when is_binary(name) -> name
        _ -> ""
      end)

    {:ok, join_values(names)}
  end

  defp parse_value(vr, %{"Value" => values}) when vr in [:AT] and is_list(values) do
    # Attribute Tag - parse from string format
    tags =
      Enum.map(values, fn
        tag_string when is_binary(tag_string) and byte_size(tag_string) == 8 ->
          case parse_tag(tag_string) do
            {:ok, tag} -> tag
            _ -> tag_string
          end

        other ->
          other
      end)

    {:ok, simplify_values(tags)}
  end

  defp parse_value(vr, %{"Value" => values})
       when vr in [:US, :SS, :UL, :SL, :FL, :FD] and is_list(values) do
    # Numeric values - keep as list if multiple
    {:ok, simplify_values(values)}
  end

  defp parse_value(vr, %{"Value" => values}) when vr in [:DS, :IS] and is_list(values) do
    # Decimal/Integer String - convert back to string format
    string_values =
      Enum.map(values, fn
        nil -> ""
        val when is_number(val) -> to_string(val)
        val -> to_string(val)
      end)

    {:ok, join_values(string_values)}
  end

  defp parse_value(_vr, %{"Value" => values}) when is_list(values) do
    # String values
    {:ok, join_values(values)}
  end

  defp parse_value(_vr, _), do: {:ok, nil}

  defp format_person_name_components(components) when is_map(components) do
    # Handle structured person name: FamilyName^GivenName^MiddleName^Prefix^Suffix
    [
      Map.get(components, "FamilyName", ""),
      Map.get(components, "GivenName", ""),
      Map.get(components, "MiddleName", ""),
      Map.get(components, "NamePrefix", ""),
      Map.get(components, "NameSuffix", "")
    ]
    |> Enum.join("^")
    |> String.trim_trailing("^")
  end

  defp join_values([single]), do: single
  defp join_values(values), do: Enum.join(values, "\\")

  defp simplify_values([single]), do: single
  defp simplify_values(values), do: values
end
