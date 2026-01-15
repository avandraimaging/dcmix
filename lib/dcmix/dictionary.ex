defmodule Dcmix.Dictionary do
  @moduledoc """
  DICOM Data Dictionary for looking up tag information.

  The dictionary is loaded at compile time from `priv/dictionary/dicom.dic`.
  It provides lookup by tag or keyword, returning information about the
  element's name, VR, and value multiplicity.
  """

  alias Dcmix.Tag

  @type entry :: %{
          tag: Tag.t(),
          keyword: String.t(),
          vr: atom() | nil,
          vm: String.t(),
          description: String.t()
        }

  @dictionary_path "priv/dictionary/dicom.dic"

  # Load and parse dictionary at compile time
  @external_resource @dictionary_path

  # Load entries at compile time
  @entries (
             case File.read(@dictionary_path) do
               {:ok, content} ->
                 content
                 |> String.split("\n")
                 |> Enum.reject(&(String.starts_with?(&1, "#") or String.trim(&1) == ""))
                 |> Enum.map(fn line ->
                   parts = String.split(line, ~r/\s+/, parts: 5)

                   case parts do
                     [group, element, vr, keyword, rest] ->
                       vm_parts = String.split(rest, ~r/\s+/, parts: 2)

                       {vm, description} =
                         case vm_parts do
                           [vm, description] -> {vm, description}
                           [vm] -> {vm, ""}
                           [] -> {"1", ""}
                         end

                       tag = {
                         String.to_integer(group, 16),
                         String.to_integer(element, 16)
                       }

                       vr_atom =
                         case vr do
                           "NONE" -> nil
                           _ -> String.to_atom(vr)
                         end

                       %{
                         tag: tag,
                         keyword: keyword,
                         vr: vr_atom,
                         vm: vm,
                         description: description
                       }

                     _ ->
                       nil
                   end
                 end)
                 |> Enum.reject(&is_nil/1)

               {:error, _} ->
                 []
             end
           )

  @by_tag Map.new(@entries, fn e -> {e.tag, e} end)
  @by_keyword Map.new(@entries, fn e -> {e.keyword, e} end)

  @doc """
  Looks up a dictionary entry by tag.

  ## Examples

      iex> Dcmix.Dictionary.lookup({0x0010, 0x0010})
      {:ok, %{tag: {0x0010, 0x0010}, keyword: "PatientName", vr: :PN, vm: "1", description: "Patient's Name"}}

      iex> Dcmix.Dictionary.lookup({0xFFFF, 0xFFFF})
      {:error, :not_found}
  """
  @spec lookup(Tag.t()) :: {:ok, entry()} | {:error, :not_found}
  def lookup(tag) do
    case Map.get(@by_tag, tag) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  @doc """
  Looks up a dictionary entry by tag, raising if not found.
  """
  @spec lookup!(Tag.t()) :: entry()
  def lookup!(tag) do
    case lookup(tag) do
      {:ok, entry} -> entry
      {:error, :not_found} -> raise ArgumentError, "Unknown tag: #{Tag.to_string(tag)}"
    end
  end

  @doc """
  Looks up a dictionary entry by keyword.

  ## Examples

      iex> Dcmix.Dictionary.lookup_keyword("PatientName")
      {:ok, %{tag: {0x0010, 0x0010}, keyword: "PatientName", vr: :PN, vm: "1", description: "Patient's Name"}}
  """
  @spec lookup_keyword(String.t()) :: {:ok, entry()} | {:error, :not_found}
  def lookup_keyword(keyword) do
    case Map.get(@by_keyword, keyword) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  @doc """
  Returns the keyword for a tag, or nil if not found.

  ## Examples

      iex> Dcmix.Dictionary.keyword({0x0010, 0x0010})
      "PatientName"
  """
  @spec keyword(Tag.t()) :: String.t() | nil
  def keyword(tag) do
    case lookup(tag) do
      {:ok, entry} -> entry.keyword
      {:error, _} -> nil
    end
  end

  @doc """
  Returns the VR for a tag from the dictionary.
  This is used when parsing Implicit VR data.

  ## Examples

      iex> Dcmix.Dictionary.vr({0x0010, 0x0010})
      :PN
  """
  @spec vr(Tag.t()) :: atom() | nil
  def vr(tag) do
    case lookup(tag) do
      {:ok, entry} -> entry.vr
      {:error, _} -> nil
    end
  end

  @doc """
  Returns the description for a tag.
  """
  @spec description(Tag.t()) :: String.t() | nil
  def description(tag) do
    case lookup(tag) do
      {:ok, entry} -> entry.description
      {:error, _} -> nil
    end
  end

  @doc """
  Returns the tag for a keyword, or nil if not found.
  """
  @spec tag(String.t()) :: Tag.t() | nil
  def tag(keyword) do
    case lookup_keyword(keyword) do
      {:ok, entry} -> entry.tag
      {:error, _} -> nil
    end
  end

  @doc """
  Returns all dictionary entries.
  """
  @spec all() :: [entry()]
  def all, do: @entries

  @doc """
  Returns the number of entries in the dictionary.
  """
  @spec size() :: non_neg_integer()
  def size, do: length(@entries)
end
