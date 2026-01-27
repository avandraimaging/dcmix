defmodule Dcmix.PrivateTag do
  @moduledoc """
  Utilities for working with DICOM private tags.

  Private tags allow vendors to store proprietary information in DICOM files.
  They use odd-numbered groups (0x0009, 0x0011, 0x0019, etc.) and require
  a "Private Creator" element to identify the vendor.

  ## Private Tag Structure

  Private tags in DICOM follow this structure:
  - Group number must be odd (0x0009, 0x0011, etc.)
  - Element 0x0010-0x00FF are reserved for Private Creator IDs
  - Element 0xXX00-0xXXFF are private data elements (XX = creator block)

  For example, if creator "ACME Corp" is registered at (0x0009, 0x0010):
  - The private data tags are (0x0009, 0x1000) through (0x0009, 0x10FF)

  ## Usage

      # Register a private creator and add data
      dataset = Dcmix.PrivateTag.register_creator(dataset, 0x0009, "ACME Corp")
      dataset = Dcmix.PrivateTag.put(dataset, 0x0009, "ACME Corp", 0x01, :LO, "Private Data")

      # Read private data
      value = Dcmix.PrivateTag.get(dataset, 0x0009, "ACME Corp", 0x01)
  """

  alias Dcmix.{Tag, DataSet, DataElement}

  @private_creator_range 0x0010..0x00FF

  @doc """
  Registers a private creator in a DataSet.

  Finds or allocates a slot in the private creator range (0x0010-0x00FF)
  for the given creator identification string.

  Returns the dataset with the creator registered and the allocated block number.

  ## Examples

      {dataset, block} = Dcmix.PrivateTag.register_creator(dataset, 0x0009, "ACME Corp")
      # block might be 0x10 if (0x0009, 0x0010) was used
  """
  @spec register_creator(DataSet.t(), non_neg_integer(), String.t()) ::
          {DataSet.t(), non_neg_integer()}
  def register_creator(%DataSet{} = dataset, group, creator) when rem(group, 2) == 1 do
    # Check if creator already registered
    case find_creator_block(dataset, group, creator) do
      {:ok, block} ->
        {dataset, block}

      :not_found ->
        # Find next available slot
        block = find_available_block(dataset, group)
        tag = {group, block}
        element = DataElement.new(tag, :LO, creator)
        {DataSet.put(dataset, element), block}
    end
  end

  @doc """
  Finds the block number for a registered private creator.

  ## Examples

      {:ok, 0x10} = Dcmix.PrivateTag.find_creator_block(dataset, 0x0009, "ACME Corp")
  """
  @spec find_creator_block(DataSet.t(), non_neg_integer(), String.t()) ::
          {:ok, non_neg_integer()} | :not_found
  def find_creator_block(%DataSet{} = dataset, group, creator) do
    result =
      Enum.find(@private_creator_range, fn element ->
        tag = {group, element}

        case DataSet.get_string(dataset, tag) do
          nil -> false
          value -> String.trim(value) == creator
        end
      end)

    case result do
      nil -> :not_found
      block -> {:ok, block}
    end
  end

  @doc """
  Puts a private data element into a DataSet.

  The creator must already be registered. The element_offset is the offset
  within the creator's block (0x00-0xFF).

  ## Examples

      # After registering "ACME Corp" at block 0x10:
      # This creates element (0x0009, 0x1001) - offset 0x01 in block 0x10
      dataset = Dcmix.PrivateTag.put(dataset, 0x0009, "ACME Corp", 0x01, :LO, "Data")
  """
  @spec put(DataSet.t(), non_neg_integer(), String.t(), non_neg_integer(), atom(), term()) ::
          DataSet.t() | {:error, term()}
  def put(%DataSet{} = dataset, group, creator, element_offset, vr, value)
      when rem(group, 2) == 1 and element_offset in 0x00..0xFF do
    case find_creator_block(dataset, group, creator) do
      {:ok, block} ->
        element = block * 0x100 + element_offset
        tag = {group, element}
        DataSet.put_element(dataset, tag, vr, value)

      :not_found ->
        {:error, {:creator_not_registered, creator}}
    end
  end

  @doc """
  Puts a private data element, automatically registering the creator if needed.

  ## Examples

      dataset = Dcmix.PrivateTag.put!(dataset, 0x0009, "ACME Corp", 0x01, :LO, "Data")
  """
  @spec put!(DataSet.t(), non_neg_integer(), String.t(), non_neg_integer(), atom(), term()) ::
          DataSet.t()
  def put!(%DataSet{} = dataset, group, creator, element_offset, vr, value) do
    {dataset, _block} = register_creator(dataset, group, creator)
    put(dataset, group, creator, element_offset, vr, value)
  end

  @doc """
  Gets a private data element value from a DataSet.

  ## Examples

      value = Dcmix.PrivateTag.get(dataset, 0x0009, "ACME Corp", 0x01)
  """
  @spec get(DataSet.t(), non_neg_integer(), String.t(), non_neg_integer()) ::
          term() | nil
  def get(%DataSet{} = dataset, group, creator, element_offset)
      when rem(group, 2) == 1 and element_offset in 0x00..0xFF do
    case find_creator_block(dataset, group, creator) do
      {:ok, block} ->
        element = block * 0x100 + element_offset
        tag = {group, element}
        DataSet.get_value(dataset, tag)

      :not_found ->
        nil
    end
  end

  @doc """
  Gets a private data element from a DataSet.
  """
  @spec get_element(DataSet.t(), non_neg_integer(), String.t(), non_neg_integer()) ::
          DataElement.t() | nil
  def get_element(%DataSet{} = dataset, group, creator, element_offset)
      when rem(group, 2) == 1 and element_offset in 0x00..0xFF do
    case find_creator_block(dataset, group, creator) do
      {:ok, block} ->
        element = block * 0x100 + element_offset
        tag = {group, element}
        DataSet.get(dataset, tag)

      :not_found ->
        nil
    end
  end

  @doc """
  Deletes a private data element from a DataSet.
  """
  @spec delete(DataSet.t(), non_neg_integer(), String.t(), non_neg_integer()) :: DataSet.t()
  def delete(%DataSet{} = dataset, group, creator, element_offset)
      when rem(group, 2) == 1 and element_offset in 0x00..0xFF do
    case find_creator_block(dataset, group, creator) do
      {:ok, block} ->
        element = block * 0x100 + element_offset
        tag = {group, element}
        DataSet.delete(dataset, tag)

      :not_found ->
        dataset
    end
  end

  @doc """
  Returns all private creators in a DataSet for a given group.

  ## Examples

      creators = Dcmix.PrivateTag.list_creators(dataset, 0x0009)
      # => [{"ACME Corp", 0x10}, {"Other Vendor", 0x11}]
  """
  @spec list_creators(DataSet.t(), non_neg_integer()) :: [{String.t(), non_neg_integer()}]
  def list_creators(%DataSet{} = dataset, group) when rem(group, 2) == 1 do
    @private_creator_range
    |> Enum.map(fn element ->
      tag = {group, element}

      case DataSet.get_string(dataset, tag) do
        nil -> nil
        value -> {String.trim(value), element}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns all private data elements for a given creator.

  ## Examples

      elements = Dcmix.PrivateTag.list_elements(dataset, 0x0009, "ACME Corp")
  """
  @spec list_elements(DataSet.t(), non_neg_integer(), String.t()) :: [DataElement.t()]
  def list_elements(%DataSet{} = dataset, group, creator) do
    case find_creator_block(dataset, group, creator) do
      {:ok, block} ->
        base_element = block * 0x100

        dataset
        |> DataSet.to_list()
        |> Enum.filter(fn %DataElement{tag: {g, e}} ->
          g == group and e >= base_element and e < base_element + 0x100
        end)

      :not_found ->
        []
    end
  end

  @doc """
  Creates a private tag from group, creator block, and offset.

  ## Examples

      tag = Dcmix.PrivateTag.make_tag(0x0009, 0x10, 0x01)
      # => {0x0009, 0x1001}
  """
  @spec make_tag(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: Tag.t()
  def make_tag(group, block, offset)
      when rem(group, 2) == 1 and block in 0x10..0xFF and offset in 0x00..0xFF do
    {group, block * 0x100 + offset}
  end

  @doc """
  Parses a private tag into its components.

  ## Examples

      {:ok, {0x10, 0x01}} = Dcmix.PrivateTag.parse_tag({0x0009, 0x1001})
  """
  @spec parse_tag(Tag.t()) :: {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, :not_private}
  def parse_tag({group, element}) when rem(group, 2) == 1 and element >= 0x1000 do
    block = div(element, 0x100)
    offset = rem(element, 0x100)
    {:ok, {block, offset}}
  end

  def parse_tag(_), do: {:error, :not_private}

  # Find the next available block for a private creator
  defp find_available_block(dataset, group) do
    used_blocks =
      @private_creator_range
      |> Enum.filter(fn element ->
        DataSet.has_tag?(dataset, {group, element})
      end)
      |> MapSet.new()

    Enum.find(@private_creator_range, fn block ->
      not MapSet.member?(used_blocks, block)
    end)
  end
end
