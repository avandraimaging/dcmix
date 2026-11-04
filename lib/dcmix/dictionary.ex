defmodule Dcmix.Dictionary do
  @moduledoc """
  DICOM Data Dictionary for looking up tag information.

  The dictionary is loaded at compile time from `priv/dictionary/dicom.dic`,
  which `scripts/generate_dictionary.exs` generates from the DICOM Standard's
  data dictionary (PS3.6). It provides lookup by tag or keyword, returning
  information about the element's name, VR, and value multiplicity.

  Repeating-group entries such as the overlay group `60xx` match any tag their
  pattern covers in an even group, so `(6002,3000)` is OverlayData. A tag PS3.6
  gives more than one VR has, as its `vr`, the one Implicit VR data is read with
  when nothing decides it: OW for "OB or OW", otherwise the first VR listed.
  `vrs/1` lists them all.
  """

  import Bitwise

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
  @entries (case File.read(@dictionary_path) do
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

                      # x matches any hex digit: the tag is the pattern with
                      # each x as 0, the mask has 0 where each x is.
                      tag = {
                        group |> String.replace("x", "0") |> String.to_integer(16),
                        element |> String.replace("x", "0") |> String.to_integer(16)
                      }

                      mask = {
                        group
                        |> String.replace(~r/[^x]/, "F")
                        |> String.replace("x", "0")
                        |> String.to_integer(16),
                        element
                        |> String.replace(~r/[^x]/, "F")
                        |> String.replace("x", "0")
                        |> String.to_integer(16)
                      }

                      # More than one VR is written default first: "US/SS".
                      vrs =
                        case vr do
                          "NONE" -> []
                          _ -> vr |> String.split("/") |> Enum.map(&String.to_atom/1)
                        end

                      {mask,
                       %{
                         tag: tag,
                         keyword: keyword,
                         vr: List.first(vrs),
                         vm: vm,
                         description: description
                       }, vrs}

                    _ ->
                      nil
                  end
                end)
                |> Enum.reject(&is_nil/1)

              {:error, _} ->
                []
            end)

  # A mask of all ones is an exact tag; anything else, a repeating group.
  @by_tag for {{0xFFFF, 0xFFFF}, e, _vrs} <- @entries, into: %{}, do: {e.tag, e}
  @repeating for {mask, e, _vrs} <- @entries, mask != {0xFFFF, 0xFFFF}, do: {mask, e}
  @by_keyword Map.new(@entries, fn {_mask, e, _vrs} -> {e.keyword, e} end)
  @all Enum.map(@entries, fn {_mask, e, _vrs} -> e end)
  @alternative_vrs for {_mask, e, [_, _ | _] = vrs} <- @entries, into: %{}, do: {e.keyword, vrs}

  @doc """
  Looks up a dictionary entry by tag.

  ## Examples

      iex> Dcmix.Dictionary.lookup({0x0010, 0x0010})
      {:ok, %{tag: {0x0010, 0x0010}, keyword: "PatientName", vr: :PN, vm: "1", description: "Patient's Name"}}

      iex> Dcmix.Dictionary.lookup({0x6002, 0x0010})
      {:ok, %{tag: {0x6002, 0x0010}, keyword: "OverlayRows", vr: :US, vm: "1", description: "Overlay Rows"}}

      iex> Dcmix.Dictionary.lookup({0xFFFF, 0xFFFF})
      {:error, :not_found}
  """
  @spec lookup(Tag.t()) :: {:ok, entry()} | {:error, :not_found}
  def lookup(tag) do
    case Map.get(@by_tag, tag) do
      nil -> lookup_repeating(tag)
      entry -> {:ok, entry}
    end
  end

  # Repeating groups are even; an odd group is private.
  defp lookup_repeating({group, element} = tag) when rem(group, 2) == 0 do
    Enum.find_value(@repeating, {:error, :not_found}, fn {{group_mask, element_mask}, entry} ->
      {pattern_group, pattern_element} = entry.tag

      if band(group, group_mask) == pattern_group and
           band(element, element_mask) == pattern_element,
         do: {:ok, %{entry | tag: tag}}
    end)
  end

  defp lookup_repeating(_tag), do: {:error, :not_found}

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
  Looks up a dictionary entry by keyword. A repeating-group entry's tag is its
  first group's, such as `(6000,0010)` for OverlayRows.

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
  Returns every VR PS3.6 gives a tag, the one `vr/1` returns first, or `[]`
  for a tag the dictionary doesn't know.

  A tag with more than one VR, such as SmallestImagePixelValue ("US or SS"),
  takes the one that applies from other elements; `vr/1` is the one Implicit
  VR data is read with when nothing decides it.

  ## Examples

      iex> Dcmix.Dictionary.vrs({0x0028, 0x0106})
      [:US, :SS]

      iex> Dcmix.Dictionary.vrs({0x0010, 0x0010})
      [:PN]
  """
  @spec vrs(Tag.t()) :: [atom()]
  def vrs(tag) do
    case lookup(tag) do
      {:ok, %{vr: nil}} -> []
      {:ok, entry} -> Map.get(@alternative_vrs, entry.keyword, [entry.vr])
      {:error, _} -> []
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
  def all, do: @all

  @doc """
  Returns the number of entries in the dictionary.
  """
  @spec size() :: non_neg_integer()
  def size, do: length(@all)
end
