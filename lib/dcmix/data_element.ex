defmodule Dcmix.DataElement do
  @moduledoc """
  Represents a single DICOM data element.

  A data element consists of a tag, value representation (VR), and value.
  The value can be a string, number, binary, list (for multiple values),
  or a list of DataSets (for sequences).
  """

  alias Dcmix.{Tag, VR}

  @type value ::
          String.t()
          | number()
          | binary()
          | [String.t()]
          | [number()]
          | [Dcmix.DataSet.t()]
          | nil

  @type t :: %__MODULE__{
          tag: Tag.t(),
          vr: VR.t() | nil,
          value: value(),
          length: non_neg_integer() | :undefined
        }

  defstruct [:tag, :vr, :value, length: 0]

  @doc """
  Creates a new data element.

  ## Examples

      iex> Dcmix.DataElement.new({0x0010, 0x0010}, :PN, "Doe^John")
      %Dcmix.DataElement{tag: {0x0010, 0x0010}, vr: :PN, value: "Doe^John", length: 0}
  """
  @spec new(Tag.t(), VR.t() | nil, value()) :: t()
  def new(tag, vr, value) do
    %__MODULE__{
      tag: tag,
      vr: vr,
      value: value,
      length: calculate_length(vr, value)
    }
  end

  @doc """
  Creates a new data element with explicit length.
  Used during parsing when length is known from the file.
  """
  @spec new(Tag.t(), VR.t() | nil, value(), non_neg_integer() | :undefined) :: t()
  def new(tag, vr, value, length) do
    %__MODULE__{
      tag: tag,
      vr: vr,
      value: value,
      length: length
    }
  end

  @doc """
  Returns the tag of the element.
  """
  @spec tag(t()) :: Tag.t()
  def tag(%__MODULE__{tag: tag}), do: tag

  @doc """
  Returns the VR of the element.
  """
  @spec vr(t()) :: VR.t() | nil
  def vr(%__MODULE__{vr: vr}), do: vr

  @doc """
  Returns the value of the element.
  """
  @spec value(t()) :: value()
  def value(%__MODULE__{value: value}), do: value

  @doc """
  Returns true if this element is a sequence.
  """
  @spec sequence?(t()) :: boolean()
  def sequence?(%__MODULE__{vr: :SQ}), do: true
  def sequence?(_), do: false

  @doc """
  Returns the items in a sequence element, or an empty list if not a sequence.
  """
  @spec items(t()) :: [Dcmix.DataSet.t()]
  def items(%__MODULE__{vr: :SQ, value: items}) when is_list(items), do: items
  def items(_), do: []

  @doc """
  Returns the string value, handling multiple values.
  For elements with VM > 1, returns the concatenated string with backslash separators.
  """
  @spec string_value(t()) :: String.t() | nil
  def string_value(%__MODULE__{value: nil}), do: nil

  def string_value(%__MODULE__{value: values}) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.join("\\")
  end

  def string_value(%__MODULE__{value: value}) when is_binary(value), do: value
  def string_value(%__MODULE__{value: value}), do: to_string(value)

  @doc """
  Returns the values as a list, splitting multi-valued string elements.
  """
  @spec values(t()) :: [String.t() | number() | binary()]
  def values(%__MODULE__{value: nil}), do: []
  def values(%__MODULE__{value: values}) when is_list(values), do: values

  def values(%__MODULE__{vr: vr, value: value}) when is_binary(value) do
    if VR.allows_multiple_values?(vr) do
      String.split(value, "\\")
    else
      [value]
    end
  end

  def values(%__MODULE__{value: value}), do: [value]

  @doc """
  Returns the first value for multi-valued elements, or the single value.
  """
  @spec first_value(t()) :: String.t() | number() | binary() | nil
  def first_value(element) do
    case values(element) do
      [] -> nil
      [first | _] -> first
    end
  end

  @doc """
  Updates the value of an element.
  """
  @spec put_value(t(), value()) :: t()
  def put_value(%__MODULE__{} = element, value) do
    %{element | value: value, length: calculate_length(element.vr, value)}
  end

  @doc """
  Returns true if the element has an undefined length.
  """
  @spec undefined_length?(t()) :: boolean()
  def undefined_length?(%__MODULE__{length: :undefined}), do: true
  def undefined_length?(_), do: false

  defp calculate_length(_vr, nil), do: 0
  defp calculate_length(_vr, value) when is_binary(value), do: byte_size(value)
  defp calculate_length(:SQ, _), do: :undefined

  defp calculate_length(vr, values) when is_list(values) do
    if VR.string?(vr) do
      values
      |> Enum.map(&to_string/1)
      |> Enum.join("\\")
      |> byte_size()
    else
      # For numeric arrays, calculate based on element size
      length(values) * element_size(vr)
    end
  end

  defp calculate_length(vr, _value) when vr in [:US, :SS], do: 2
  defp calculate_length(vr, _value) when vr in [:UL, :SL, :FL], do: 4
  defp calculate_length(vr, _value) when vr in [:FD], do: 8
  defp calculate_length(vr, _value) when vr in [:AT], do: 4
  defp calculate_length(_, _), do: 0

  defp element_size(vr) when vr in [:US, :SS], do: 2
  defp element_size(vr) when vr in [:UL, :SL, :FL], do: 4
  defp element_size(vr) when vr in [:FD, :OD], do: 8
  defp element_size(:AT), do: 4
  defp element_size(_), do: 1
end
