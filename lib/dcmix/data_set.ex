defmodule Dcmix.DataSet do
  @moduledoc """
  Represents a collection of DICOM data elements.

  A DataSet maintains both the order of elements (important for DICOM)
  and provides fast O(1) lookup by tag. It's used to represent both
  the top-level DICOM object and nested sequence items.
  """

  alias Dcmix.{Tag, DataElement}

  @type t :: %__MODULE__{
          elements: [DataElement.t()],
          index: %{Tag.t() => DataElement.t()}
        }

  defstruct elements: [], index: %{}

  @doc """
  Creates a new empty DataSet.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a DataSet from a list of elements.
  """
  @spec new([DataElement.t()]) :: t()
  def new(elements) when is_list(elements) do
    index = Map.new(elements, fn elem -> {elem.tag, elem} end)
    %__MODULE__{elements: elements, index: index}
  end

  @doc """
  Gets an element by tag.

  ## Examples

      iex> ds = Dcmix.DataSet.new([Dcmix.DataElement.new({0x0010, 0x0010}, :PN, "Doe^John")])
      iex> Dcmix.DataSet.get(ds, {0x0010, 0x0010})
      %Dcmix.DataElement{tag: {0x0010, 0x0010}, vr: :PN, value: "Doe^John"}
  """
  @spec get(t(), Tag.t()) :: DataElement.t() | nil
  def get(%__MODULE__{index: index}, tag) do
    Map.get(index, tag)
  end

  @doc """
  Gets the value of an element by tag.
  """
  @spec get_value(t(), Tag.t()) :: DataElement.value() | nil
  def get_value(%__MODULE__{} = ds, tag) do
    case get(ds, tag) do
      nil -> nil
      element -> element.value
    end
  end

  @doc """
  Gets the string value of an element by tag.
  """
  @spec get_string(t(), Tag.t()) :: String.t() | nil
  def get_string(%__MODULE__{} = ds, tag) do
    case get(ds, tag) do
      nil -> nil
      element -> DataElement.string_value(element)
    end
  end

  @doc """
  Returns true if the DataSet contains an element with the given tag.
  """
  @spec has_tag?(t(), Tag.t()) :: boolean()
  def has_tag?(%__MODULE__{index: index}, tag) do
    Map.has_key?(index, tag)
  end

  @doc """
  Adds or updates an element in the DataSet.
  Maintains proper tag ordering.
  """
  @spec put(t(), DataElement.t()) :: t()
  def put(%__MODULE__{elements: elements, index: index}, element) do
    tag = element.tag

    if Map.has_key?(index, tag) do
      # Update existing element
      new_elements = Enum.map(elements, fn e ->
        if e.tag == tag, do: element, else: e
      end)
      %__MODULE__{elements: new_elements, index: Map.put(index, tag, element)}
    else
      # Insert new element in proper order
      new_elements = insert_sorted(elements, element)
      %__MODULE__{elements: new_elements, index: Map.put(index, tag, element)}
    end
  end

  @doc """
  Adds an element with the given tag, VR, and value.
  """
  @spec put_element(t(), Tag.t(), Dcmix.VR.t(), DataElement.value()) :: t()
  def put_element(%__MODULE__{} = ds, tag, vr, value) do
    put(ds, DataElement.new(tag, vr, value))
  end

  @doc """
  Removes an element by tag.
  """
  @spec delete(t(), Tag.t()) :: t()
  def delete(%__MODULE__{elements: elements, index: index}, tag) do
    new_elements = Enum.reject(elements, fn e -> e.tag == tag end)
    %__MODULE__{elements: new_elements, index: Map.delete(index, tag)}
  end

  @doc """
  Returns the number of elements in the DataSet.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{elements: elements}), do: length(elements)

  @doc """
  Returns all elements in order.
  """
  @spec to_list(t()) :: [DataElement.t()]
  def to_list(%__MODULE__{elements: elements}), do: elements

  @doc """
  Returns all tags in order.
  """
  @spec tags(t()) :: [Tag.t()]
  def tags(%__MODULE__{elements: elements}) do
    Enum.map(elements, & &1.tag)
  end

  @doc """
  Merges another DataSet into this one.
  Elements from the second DataSet override elements with the same tag.
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = ds1, %__MODULE__{} = ds2) do
    Enum.reduce(ds2.elements, ds1, fn elem, acc ->
      put(acc, elem)
    end)
  end

  @doc """
  Filters elements by a predicate function.
  """
  @spec filter(t(), (DataElement.t() -> boolean())) :: t()
  def filter(%__MODULE__{elements: elements}, predicate) do
    new_elements = Enum.filter(elements, predicate)
    new(new_elements)
  end

  @doc """
  Returns elements in a specific group.
  """
  @spec group(t(), non_neg_integer()) :: [DataElement.t()]
  def group(%__MODULE__{elements: elements}, group_number) do
    Enum.filter(elements, fn e ->
      {g, _} = e.tag
      g == group_number
    end)
  end

  @doc """
  Returns the file meta information elements (group 0002).
  """
  @spec file_meta(t()) :: [DataElement.t()]
  def file_meta(%__MODULE__{} = ds), do: group(ds, 0x0002)

  @doc """
  Splits the DataSet into file meta and data set portions.
  """
  @spec split_file_meta(t()) :: {t(), t()}
  def split_file_meta(%__MODULE__{elements: elements}) do
    {meta_elements, data_elements} = Enum.split_with(elements, fn e ->
      {g, _} = e.tag
      g == 0x0002
    end)
    {new(meta_elements), new(data_elements)}
  end

  # Insert element in sorted order by tag
  defp insert_sorted([], element), do: [element]

  defp insert_sorted([head | tail] = list, element) do
    case Tag.compare(element.tag, head.tag) do
      :lt -> [element | list]
      :eq -> [element | tail]
      :gt -> [head | insert_sorted(tail, element)]
    end
  end

  defimpl Enumerable do
    def count(%Dcmix.DataSet{elements: elements}), do: {:ok, length(elements)}

    def member?(%Dcmix.DataSet{index: index}, %Dcmix.DataElement{tag: tag}) do
      {:ok, Map.has_key?(index, tag)}
    end

    def member?(_, _), do: {:ok, false}

    def reduce(%Dcmix.DataSet{elements: elements}, acc, fun) do
      Enumerable.List.reduce(elements, acc, fun)
    end

    def slice(%Dcmix.DataSet{elements: elements}) do
      {:ok, length(elements), &Enum.slice(elements, &1, &2)}
    end
  end
end
