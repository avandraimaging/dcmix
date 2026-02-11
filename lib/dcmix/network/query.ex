defmodule Dcmix.Network.Query do
  @moduledoc """
  CLI-style query builder for C-FIND operations.

  Parses query term strings (similar to dcmtk's `-k` option) into
  `Dcmix.DataSet` structures suitable for use as C-FIND identifier datasets.

  ## Query Term Syntax

  - `"Keyword"` — Include the tag with an empty value (wildcard match)
  - `"Keyword=Value"` — Include the tag with the specified value (exact or range match)

  ## Examples

      {:ok, dataset} = Dcmix.Network.Query.parse_terms([
        "PatientName",
        "StudyDate=20250708",
        "StudyTime=070000-073000"
      ])

  Automatically adds `QueryRetrieveLevel=STUDY` if not already present.
  This default can be overridden by including an explicit `QueryRetrieveLevel` term.
  """

  alias Dcmix.{DataElement, DataSet, Dictionary}

  @query_retrieve_level_tag {0x0008, 0x0052}

  @doc """
  Parses a list of query terms into a DataSet.

  Automatically adds `QueryRetrieveLevel=STUDY` if not present in the terms.
  When a keyword appears multiple times, later values override earlier ones.
  """
  @spec parse_terms([String.t()]) :: {:ok, DataSet.t()} | {:error, term()}
  def parse_terms(terms) when is_list(terms) do
    result =
      Enum.reduce_while(terms, {:ok, DataSet.new()}, fn term, {:ok, ds} ->
        case parse_term(term) do
          {:ok, {tag, vr, value}} ->
            {:cont, {:ok, DataSet.put(ds, DataElement.new(tag, vr, value))}}

          {:error, _} = error ->
            {:halt, error}
        end
      end)

    case result do
      {:ok, ds} -> {:ok, ensure_query_retrieve_level(ds)}
      error -> error
    end
  end

  @doc """
  Parses a single query term into `{tag, vr, value}`.

  Returns `{:error, {:unknown_keyword, keyword}}` if the keyword
  is not found in the DICOM dictionary.
  """
  @spec parse_term(String.t()) :: {:ok, {Dcmix.Tag.t(), atom(), String.t()}} | {:error, term()}
  def parse_term(term) do
    {keyword, value} =
      case String.split(term, "=", parts: 2) do
        [kw, val] -> {kw, val}
        [kw] -> {kw, ""}
      end

    case Dictionary.lookup_keyword(keyword) do
      {:ok, entry} ->
        {:ok, {entry.tag, entry.vr, value}}

      {:error, :not_found} ->
        {:error, {:unknown_keyword, keyword}}
    end
  end

  defp ensure_query_retrieve_level(ds) do
    if DataSet.has_tag?(ds, @query_retrieve_level_tag) do
      ds
    else
      DataSet.put(ds, DataElement.new(@query_retrieve_level_tag, :CS, "STUDY"))
    end
  end
end
