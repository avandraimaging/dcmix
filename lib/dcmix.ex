defmodule Dcmix do
  @moduledoc """
  Dcmix - A DICOM library for Elixir.

  Dcmix provides functionality for reading, writing, and manipulating DICOM files.
  It supports multiple transfer syntaxes and provides export to JSON and XML formats.

  ## Reading DICOM Files

      {:ok, dataset} = Dcmix.read_file("/path/to/file.dcm")
      patient_name = Dcmix.get_string(dataset, {0x0010, 0x0010})

  ## Writing DICOM Files

      dataset = Dcmix.DataSet.new()
      |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")
      |> Dcmix.DataSet.put_element({0x0010, 0x0020}, :LO, "12345")

      Dcmix.write_file(dataset, "/path/to/output.dcm")

  ## Exporting to JSON

      {:ok, json} = Dcmix.to_json(dataset)

  ## Using Tags

  Tags can be specified as tuples `{group, element}` or by keyword:

      Dcmix.get_string(dataset, {0x0010, 0x0010})
      Dcmix.get_string(dataset, "PatientName")
  """

  alias Dcmix.{DataSet, DataElement, Tag, Dictionary, Parser, Writer}

  @doc """
  Reads a DICOM file and returns the parsed DataSet.

  ## Options
  - `:force_transfer_syntax` - Override the transfer syntax from file meta

  ## Examples

      {:ok, dataset} = Dcmix.read_file("/path/to/file.dcm")
  """
  @spec read_file(Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  defdelegate read_file(path, opts \\ []), to: Parser, as: :parse_file

  @doc """
  Parses DICOM data from binary.
  """
  @spec parse(binary(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  defdelegate parse(data, opts \\ []), to: Parser

  @doc """
  Writes a DataSet to a DICOM file.

  ## Options
  - `:transfer_syntax` - Transfer syntax to use (default: Explicit VR Little Endian)
  - `:implementation_class_uid` - Implementation Class UID
  - `:implementation_version_name` - Implementation Version Name

  ## Examples

      :ok = Dcmix.write_file(dataset, "/path/to/output.dcm")
  """
  @spec write_file(DataSet.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  defdelegate write_file(dataset, path, opts \\ []), to: Writer

  @doc """
  Encodes a DataSet to DICOM binary format.
  """
  @spec encode(DataSet.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  defdelegate encode(dataset, opts \\ []), to: Writer

  @doc """
  Gets the value of an element by tag or keyword.

  ## Examples

      value = Dcmix.get(dataset, {0x0010, 0x0010})
      value = Dcmix.get(dataset, "PatientName")
  """
  @spec get(DataSet.t(), Tag.t() | String.t()) :: DataElement.value() | nil
  def get(dataset, tag) when is_tuple(tag) do
    DataSet.get_value(dataset, tag)
  end

  def get(dataset, keyword) when is_binary(keyword) do
    case Dictionary.tag(keyword) do
      nil -> nil
      tag -> DataSet.get_value(dataset, tag)
    end
  end

  @doc """
  Gets the string value of an element by tag or keyword.

  ## Examples

      patient_name = Dcmix.get_string(dataset, {0x0010, 0x0010})
      patient_name = Dcmix.get_string(dataset, "PatientName")
  """
  @spec get_string(DataSet.t(), Tag.t() | String.t()) :: String.t() | nil
  def get_string(dataset, tag) when is_tuple(tag) do
    DataSet.get_string(dataset, tag)
  end

  def get_string(dataset, keyword) when is_binary(keyword) do
    case Dictionary.tag(keyword) do
      nil -> nil
      tag -> DataSet.get_string(dataset, tag)
    end
  end

  @doc """
  Gets an element by tag or keyword.
  """
  @spec get_element(DataSet.t(), Tag.t() | String.t()) :: DataElement.t() | nil
  def get_element(dataset, tag) when is_tuple(tag) do
    DataSet.get(dataset, tag)
  end

  def get_element(dataset, keyword) when is_binary(keyword) do
    case Dictionary.tag(keyword) do
      nil -> nil
      tag -> DataSet.get(dataset, tag)
    end
  end

  @doc """
  Puts a value into the dataset.

  ## Examples

      dataset = Dcmix.put(dataset, {0x0010, 0x0010}, :PN, "Doe^John")
      dataset = Dcmix.put(dataset, "PatientName", :PN, "Doe^John")
  """
  @spec put(DataSet.t(), Tag.t() | String.t(), atom(), DataElement.value()) :: DataSet.t()
  def put(dataset, tag, vr, value) when is_tuple(tag) do
    DataSet.put_element(dataset, tag, vr, value)
  end

  def put(dataset, keyword, vr, value) when is_binary(keyword) do
    case Dictionary.tag(keyword) do
      nil -> raise ArgumentError, "Unknown DICOM keyword: #{keyword}"
      tag -> DataSet.put_element(dataset, tag, vr, value)
    end
  end

  @doc """
  Deletes an element from the dataset.
  """
  @spec delete(DataSet.t(), Tag.t() | String.t()) :: DataSet.t()
  def delete(dataset, tag) when is_tuple(tag) do
    DataSet.delete(dataset, tag)
  end

  def delete(dataset, keyword) when is_binary(keyword) do
    case Dictionary.tag(keyword) do
      nil -> dataset
      tag -> DataSet.delete(dataset, tag)
    end
  end

  @doc """
  Converts the dataset to JSON format (DICOM JSON Model per PS3.18 F.2).
  """
  @spec to_json(DataSet.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def to_json(dataset, opts \\ []) do
    Dcmix.Export.JSON.encode(dataset, opts)
  end

  @doc """
  Converts the dataset to XML format (Native DICOM Model).
  """
  @spec to_xml(DataSet.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def to_xml(dataset, opts \\ []) do
    Dcmix.Export.XML.encode(dataset, opts)
  end

  @doc """
  Dumps the dataset contents to a human-readable string.
  """
  @spec dump(DataSet.t(), keyword()) :: String.t()
  def dump(dataset, opts \\ []) do
    Dcmix.Export.Text.encode(dataset, opts)
  end

  @doc """
  Exports pixel data from the dataset to an image file.

  The output format is inferred from the file extension (.png, .ppm, .pgm)
  or can be explicitly specified with the `:format` option.

  ## Options

  - `:frame` - Frame number for multi-frame images (0-indexed, default: 0)
  - `:window` - Windowing for grayscale images:
    - `:auto` - Use VOI LUT from DICOM tags if available, else min/max (default)
    - `:min_max` - Window based on actual min/max pixel values
    - `:none` - No windowing
    - `{center, width}` - Explicit window center and width
  - `:format` - Output format (:png, :ppm, :pgm)

  ## Examples

      :ok = Dcmix.to_image(dataset, "output.png")
      :ok = Dcmix.to_image(dataset, "output.png", frame: 0, window: :auto)
  """
  @spec to_image(DataSet.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def to_image(dataset, path, opts \\ []) do
    Dcmix.Export.Image.to_file(dataset, path, opts)
  end

  @doc """
  Returns the transfer syntax UID from a DICOM file without parsing the full dataset.
  """
  @spec get_transfer_syntax(Path.t()) :: {:ok, String.t()} | {:error, term()}
  defdelegate get_transfer_syntax(path), to: Parser

  @doc """
  Creates a new empty DataSet.
  """
  @spec new() :: DataSet.t()
  defdelegate new(), to: DataSet

  # ============================================================================
  # Import Functions (JSON/XML/Image -> DICOM)
  # ============================================================================

  @doc """
  Creates a DataSet from a JSON string (DICOM JSON Model per PS3.18 F.2).

  This is the inverse of `to_json/2`.

  ## Options
  - `:template` - An existing DataSet to merge the JSON data into

  ## Examples

      {:ok, dataset} = Dcmix.from_json(json_string)
      {:ok, dataset} = Dcmix.from_json(json_string, template: existing_dataset)
  """
  @spec from_json(String.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def from_json(json_string, opts \\ []) do
    Dcmix.Import.JSON.decode(json_string, opts)
  end

  @doc """
  Creates a DataSet from a JSON file.

  ## Examples

      {:ok, dataset} = Dcmix.from_json_file("data.json")
  """
  @spec from_json_file(Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def from_json_file(path, opts \\ []) do
    Dcmix.Import.JSON.decode_file(path, opts)
  end

  @doc """
  Creates a DataSet from an XML string (Native DICOM Model per PS3.19).

  This is the inverse of `to_xml/2`.

  ## Options
  - `:template` - An existing DataSet to merge the XML data into

  ## Examples

      {:ok, dataset} = Dcmix.from_xml(xml_string)
      {:ok, dataset} = Dcmix.from_xml(xml_string, template: existing_dataset)
  """
  @spec from_xml(String.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def from_xml(xml_string, opts \\ []) do
    Dcmix.Import.XML.decode(xml_string, opts)
  end

  @doc """
  Creates a DataSet from an XML file.

  ## Examples

      {:ok, dataset} = Dcmix.from_xml_file("data.xml")
  """
  @spec from_xml_file(Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def from_xml_file(path, opts \\ []) do
    Dcmix.Import.XML.decode_file(path, opts)
  end

  @doc """
  Creates a DataSet from an image file (PNG, JPEG).

  Similar to dcmtk's `img2dcm`.

  ## Options

  - `:dataset_from` - Template DataSet to use as base (like dcmtk's --dataset-from)
  - `:study_from` - DataSet to copy patient/study info from (like dcmtk's --study-from)
  - `:series_from` - DataSet to copy patient/study/series info from (like dcmtk's --series-from)
  - `:sop_class` - SOP Class to use (:secondary_capture, :vl_photo, default: :secondary_capture)
  - `:insert_type2` - Auto-insert missing Type 2 attributes (default: true)
  - `:invent_type1` - Auto-generate missing Type 1 values (default: true)

  ## Examples

      {:ok, dataset} = Dcmix.from_image("photo.png")
      {:ok, dataset} = Dcmix.from_image("photo.png", dataset_from: template)
      {:ok, dataset} = Dcmix.from_image("photo.png", series_from: source_dicom)
  """
  @spec from_image(Path.t(), keyword()) :: {:ok, DataSet.t()} | {:error, term()}
  def from_image(path, opts \\ []) do
    Dcmix.Import.Image.from_file(path, opts)
  end
end
