defmodule Dcmix.Writer do
  @moduledoc """
  DICOM file writer.

  Writes DICOM Part 10 files with proper file meta information
  and configurable transfer syntax.
  """

  alias Dcmix.{Tag, DataSet}
  alias Dcmix.Parser.TransferSyntax
  alias Dcmix.Writer.{ExplicitVR, ImplicitVR}

  @preamble_size 128
  @dicm_prefix "DICM"
  @implementation_class_uid "1.2.826.0.1.3680043.9.7433.1.1"
  @implementation_version_name "DCMIX_001"
  @source_application_entity_title {0x0002, 0x0016}

  @doc """
  Writes a DataSet to a DICOM file.

  ## Options
  - `:transfer_syntax` - Transfer syntax UID (default: Explicit VR Little Endian)
  - `:implementation_class_uid` - Override implementation class UID
  - `:implementation_version_name` - Override implementation version name
  """
  @spec write_file(DataSet.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def write_file(%DataSet{} = dataset, path, opts \\ []) do
    {:ok, data} = encode(dataset, opts)
    File.write(path, data)
  end

  @doc """
  Encodes a DataSet to DICOM binary format.
  """
  @spec encode(DataSet.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%DataSet{} = dataset, opts \\ []) do
    transfer_syntax_uid =
      Keyword.get(opts, :transfer_syntax, TransferSyntax.explicit_vr_little_endian())

    impl_class_uid =
      Keyword.get(opts, :implementation_class_uid, @implementation_class_uid)

    impl_version_name =
      Keyword.get(opts, :implementation_version_name, @implementation_version_name)

    # Split out file meta and data elements
    {existing_file_meta, data_elements} = DataSet.split_file_meta(dataset)

    # Get SOP Class UID and SOP Instance UID from data elements
    sop_class_uid =
      DataSet.get_value(data_elements, Tag.sop_class_uid()) ||
        DataSet.get_value(existing_file_meta, Tag.media_storage_sop_class_uid()) ||
        ""

    sop_instance_uid =
      DataSet.get_value(data_elements, Tag.sop_instance_uid()) ||
        DataSet.get_value(existing_file_meta, Tag.media_storage_sop_instance_uid()) ||
        ""

    header =
      file_meta_header(sop_class_uid, sop_instance_uid, transfer_syntax_uid,
        implementation_class_uid: impl_class_uid,
        implementation_version_name: impl_version_name
      )

    # Encode data elements based on transfer syntax
    data_bytes = encode_data(data_elements, transfer_syntax_uid)

    {:ok, header <> data_bytes}
  end

  @doc """
  Encodes the Part 10 header: 128-byte preamble, `"DICM"` and the File Meta
  Information group (always Explicit VR Little Endian).

  Used to write a data set that is already encoded, such as one received
  over the network.

  ## Options
  - `:implementation_class_uid` - Override implementation class UID
  - `:implementation_version_name` - Override implementation version name
  - `:source_ae_title` - Adds Source Application Entity Title (0002,0016)
  """
  @spec file_meta_header(String.t(), String.t(), String.t(), keyword()) :: binary()
  def file_meta_header(sop_class_uid, sop_instance_uid, transfer_syntax_uid, opts \\ []) do
    impl_class_uid =
      Keyword.get(opts, :implementation_class_uid, @implementation_class_uid)

    impl_version_name =
      Keyword.get(opts, :implementation_version_name, @implementation_version_name)

    file_meta =
      DataSet.new()
      |> DataSet.put_element(Tag.file_meta_information_version(), :OB, <<0, 1>>)
      |> DataSet.put_element(Tag.media_storage_sop_class_uid(), :UI, sop_class_uid)
      |> DataSet.put_element(Tag.media_storage_sop_instance_uid(), :UI, sop_instance_uid)
      |> DataSet.put_element(Tag.transfer_syntax_uid(), :UI, transfer_syntax_uid)
      |> DataSet.put_element(Tag.implementation_class_uid(), :UI, impl_class_uid)
      |> DataSet.put_element(Tag.implementation_version_name(), :SH, impl_version_name)
      |> put_source_ae_title(Keyword.get(opts, :source_ae_title))

    file_meta_bytes = file_meta |> with_group_length() |> ExplicitVR.encode(big_endian: false)
    preamble = :binary.copy(<<0>>, @preamble_size)

    IO.iodata_to_binary([preamble, @dicm_prefix, file_meta_bytes])
  end

  defp put_source_ae_title(file_meta, nil), do: file_meta

  defp put_source_ae_title(file_meta, ae_title),
    do: DataSet.put_element(file_meta, @source_application_entity_title, :AE, ae_title)

  defp with_group_length(file_meta) do
    file_meta_bytes = ExplicitVR.encode(file_meta, big_endian: false)
    group_length = byte_size(file_meta_bytes)

    DataSet.new()
    |> DataSet.put_element(Tag.file_meta_information_group_length(), :UL, group_length)
    |> DataSet.merge(file_meta)
  end

  defp encode_data(data_elements, transfer_syntax_uid) do
    case TransferSyntax.lookup(transfer_syntax_uid) do
      {:ok, ts} ->
        if ts.explicit_vr do
          ExplicitVR.encode(data_elements, big_endian: ts.big_endian)
        else
          ImplicitVR.encode(data_elements)
        end

      {:error, :unknown_transfer_syntax} ->
        # Default to Explicit VR Little Endian
        ExplicitVR.encode(data_elements, big_endian: false)
    end
  end

  @doc """
  Generates a new UID based on the implementation root.

  ## Examples

      iex> Dcmix.Writer.generate_uid()
      "1.2.826.0.1.3680043.9.7433.1.20240115.123456.12345"
  """
  @spec generate_uid() :: String.t()
  def generate_uid do
    timestamp = DateTime.utc_now()

    date_part =
      Calendar.strftime(timestamp, "%Y%m%d")

    time_part =
      Calendar.strftime(timestamp, "%H%M%S")

    random_part = :rand.uniform(99_999)

    "1.2.826.0.1.3680043.9.7433.1.#{date_part}.#{time_part}.#{random_part}"
  end
end
