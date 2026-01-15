defmodule Dcmix.VR do
  @moduledoc """
  DICOM Value Representations (VR).

  A VR specifies the data type and format of the value contained in a
  Data Element. DICOM defines 27 VRs, each with specific rules about
  character repertoire, length, padding, and value multiplicity.
  """

  @type t ::
          :AE
          | :AS
          | :AT
          | :CS
          | :DA
          | :DS
          | :DT
          | :FL
          | :FD
          | :IS
          | :LO
          | :LT
          | :OB
          | :OD
          | :OF
          | :OL
          | :OW
          | :PN
          | :SH
          | :SL
          | :SQ
          | :SS
          | :ST
          | :TM
          | :UC
          | :UI
          | :UL
          | :UN
          | :UR
          | :US
          | :UT

  @vr_definitions %{
    AE: %{
      name: "Application Entity",
      max_length: 16,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    AS: %{
      name: "Age String",
      max_length: 4,
      fixed_length: true,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    AT: %{
      name: "Attribute Tag",
      max_length: 4,
      fixed_length: true,
      padding: nil,
      header_length: :short,
      string: false
    },
    CS: %{
      name: "Code String",
      max_length: 16,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    DA: %{
      name: "Date",
      max_length: 8,
      fixed_length: true,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    DS: %{
      name: "Decimal String",
      max_length: 16,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    DT: %{
      name: "Date Time",
      max_length: 26,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    FL: %{
      name: "Floating Point Single",
      max_length: 4,
      fixed_length: true,
      padding: nil,
      header_length: :short,
      string: false
    },
    FD: %{
      name: "Floating Point Double",
      max_length: 8,
      fixed_length: true,
      padding: nil,
      header_length: :short,
      string: false
    },
    IS: %{
      name: "Integer String",
      max_length: 12,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    LO: %{
      name: "Long String",
      max_length: 64,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    LT: %{
      name: "Long Text",
      max_length: 10_240,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    OB: %{
      name: "Other Byte",
      max_length: :unlimited,
      fixed_length: false,
      padding: 0x00,
      header_length: :long,
      string: false
    },
    OD: %{
      name: "Other Double",
      max_length: :unlimited,
      fixed_length: false,
      padding: nil,
      header_length: :long,
      string: false
    },
    OF: %{
      name: "Other Float",
      max_length: :unlimited,
      fixed_length: false,
      padding: nil,
      header_length: :long,
      string: false
    },
    OL: %{
      name: "Other Long",
      max_length: :unlimited,
      fixed_length: false,
      padding: nil,
      header_length: :long,
      string: false
    },
    OW: %{
      name: "Other Word",
      max_length: :unlimited,
      fixed_length: false,
      padding: nil,
      header_length: :long,
      string: false
    },
    PN: %{
      name: "Person Name",
      max_length: 64,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    SH: %{
      name: "Short String",
      max_length: 16,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    SL: %{
      name: "Signed Long",
      max_length: 4,
      fixed_length: true,
      padding: nil,
      header_length: :short,
      string: false
    },
    SQ: %{
      name: "Sequence of Items",
      max_length: :unlimited,
      fixed_length: false,
      padding: nil,
      header_length: :long,
      string: false
    },
    SS: %{
      name: "Signed Short",
      max_length: 2,
      fixed_length: true,
      padding: nil,
      header_length: :short,
      string: false
    },
    ST: %{
      name: "Short Text",
      max_length: 1024,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    TM: %{
      name: "Time",
      max_length: 14,
      fixed_length: false,
      padding: 0x20,
      header_length: :short,
      string: true
    },
    UC: %{
      name: "Unlimited Characters",
      max_length: :unlimited,
      fixed_length: false,
      padding: 0x20,
      header_length: :long,
      string: true
    },
    UI: %{
      name: "Unique Identifier (UID)",
      max_length: 64,
      fixed_length: false,
      padding: 0x00,
      header_length: :short,
      string: true
    },
    UL: %{
      name: "Unsigned Long",
      max_length: 4,
      fixed_length: true,
      padding: nil,
      header_length: :short,
      string: false
    },
    UN: %{
      name: "Unknown",
      max_length: :unlimited,
      fixed_length: false,
      padding: 0x00,
      header_length: :long,
      string: false
    },
    UR: %{
      name: "Universal Resource Identifier",
      max_length: :unlimited,
      fixed_length: false,
      padding: 0x20,
      header_length: :long,
      string: true
    },
    US: %{
      name: "Unsigned Short",
      max_length: 2,
      fixed_length: true,
      padding: nil,
      header_length: :short,
      string: false
    },
    UT: %{
      name: "Unlimited Text",
      max_length: :unlimited,
      fixed_length: false,
      padding: 0x20,
      header_length: :long,
      string: true
    }
  }

  @all_vrs Map.keys(@vr_definitions)

  @doc """
  Returns a list of all valid VR atoms.
  """
  @spec all() :: [t()]
  def all, do: @all_vrs

  @doc """
  Returns true if the given atom is a valid VR.
  """
  @spec valid?(atom()) :: boolean()
  def valid?(vr) when is_atom(vr), do: Map.has_key?(@vr_definitions, vr)
  def valid?(_), do: false

  @doc """
  Parses a 2-character VR string into an atom.

  ## Examples

      iex> Dcmix.VR.parse("CS")
      {:ok, :CS}

      iex> Dcmix.VR.parse("XX")
      {:error, "Unknown VR: XX"}
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(string) when is_binary(string) and byte_size(string) == 2 do
    try do
      vr = String.to_existing_atom(string)

      if valid?(vr) do
        {:ok, vr}
      else
        {:error, "Unknown VR: #{string}"}
      end
    rescue
      ArgumentError -> {:error, "Unknown VR: #{string}"}
    end
  end

  def parse(string), do: {:error, "Invalid VR string: #{inspect(string)}"}

  @doc """
  Converts a VR atom to its 2-character string representation.
  """
  @spec to_string(t()) :: String.t()
  def to_string(vr) when is_atom(vr), do: Atom.to_string(vr)

  @doc """
  Returns the human-readable name of a VR.

  ## Examples

      iex> Dcmix.VR.name(:PN)
      "Person Name"
  """
  @spec name(t()) :: String.t()
  def name(vr), do: get_property(vr, :name)

  @doc """
  Returns the maximum length for a VR, or :unlimited.
  """
  @spec max_length(t()) :: non_neg_integer() | :unlimited
  def max_length(vr), do: get_property(vr, :max_length)

  @doc """
  Returns true if the VR has a fixed length.
  """
  @spec fixed_length?(t()) :: boolean()
  def fixed_length?(vr), do: get_property(vr, :fixed_length)

  @doc """
  Returns the padding byte for a VR, or nil if not applicable.
  """
  @spec padding(t()) :: byte() | nil
  def padding(vr), do: get_property(vr, :padding)

  @doc """
  Returns :short (2-byte length) or :long (4-byte length with 2-byte reserved).

  In Explicit VR encoding, some VRs use a 2-byte length field (:short),
  while others use a 2-byte reserved field followed by a 4-byte length (:long).
  """
  @spec header_length(t()) :: :short | :long
  def header_length(vr), do: get_property(vr, :header_length)

  @doc """
  Returns true if the VR uses a 4-byte length field in Explicit VR encoding.
  """
  @spec long_length?(t()) :: boolean()
  def long_length?(vr), do: header_length(vr) == :long

  @doc """
  Returns true if the VR contains string data.
  """
  @spec string?(t()) :: boolean()
  def string?(vr), do: get_property(vr, :string)

  @doc """
  Returns true if the VR can contain multiple values (VM > 1).
  """
  @spec allows_multiple_values?(t()) :: boolean()
  def allows_multiple_values?(vr) do
    # String VRs with backslash as separator can have multiple values
    # SQ is special - it has multiple items, not multiple values
    string?(vr) and vr != :LT and vr != :ST and vr != :UT and vr != :UR
  end

  defp get_property(vr, property) do
    case Map.get(@vr_definitions, vr) do
      nil -> raise ArgumentError, "Unknown VR: #{inspect(vr)}"
      definition -> Map.get(definition, property)
    end
  end
end
