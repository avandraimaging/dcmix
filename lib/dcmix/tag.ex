defmodule Dcmix.Tag do
  @moduledoc """
  Represents a DICOM tag as a {group, element} tuple.

  DICOM tags are 32-bit identifiers split into a 16-bit group number
  and a 16-bit element number. Tags are typically written in hexadecimal
  format like (0008,0010) for PatientName.
  """

  @type t :: {group :: non_neg_integer(), element :: non_neg_integer()}

  # Well-known tags
  @file_meta_information_group_length {0x0002, 0x0000}
  @file_meta_information_version {0x0002, 0x0001}
  @media_storage_sop_class_uid {0x0002, 0x0002}
  @media_storage_sop_instance_uid {0x0002, 0x0003}
  @transfer_syntax_uid {0x0002, 0x0010}
  @implementation_class_uid {0x0002, 0x0012}
  @implementation_version_name {0x0002, 0x0013}

  @specific_character_set {0x0008, 0x0005}
  @image_type {0x0008, 0x0008}
  @sop_class_uid {0x0008, 0x0016}
  @sop_instance_uid {0x0008, 0x0018}
  @study_date {0x0008, 0x0020}
  @series_date {0x0008, 0x0021}
  @acquisition_date {0x0008, 0x0022}
  @content_date {0x0008, 0x0023}
  @study_time {0x0008, 0x0030}
  @modality {0x0008, 0x0060}

  @patient_name {0x0010, 0x0010}
  @patient_id {0x0010, 0x0020}
  @patient_birth_date {0x0010, 0x0030}
  @patient_sex {0x0010, 0x0040}

  @study_instance_uid {0x0020, 0x000D}
  @series_instance_uid {0x0020, 0x000E}
  @study_id {0x0020, 0x0010}
  @series_number {0x0020, 0x0011}
  @instance_number {0x0020, 0x0013}

  @samples_per_pixel {0x0028, 0x0002}
  @photometric_interpretation {0x0028, 0x0004}
  @rows {0x0028, 0x0010}
  @columns {0x0028, 0x0011}
  @bits_allocated {0x0028, 0x0100}
  @bits_stored {0x0028, 0x0101}
  @high_bit {0x0028, 0x0102}
  @pixel_representation {0x0028, 0x0103}

  @pixel_data {0x7FE0, 0x0010}

  @item {0xFFFE, 0xE000}
  @item_delimitation_item {0xFFFE, 0xE00D}
  @sequence_delimitation_item {0xFFFE, 0xE0DD}

  # Accessors for well-known tags
  def file_meta_information_group_length, do: @file_meta_information_group_length
  def file_meta_information_version, do: @file_meta_information_version
  def media_storage_sop_class_uid, do: @media_storage_sop_class_uid
  def media_storage_sop_instance_uid, do: @media_storage_sop_instance_uid
  def transfer_syntax_uid, do: @transfer_syntax_uid
  def implementation_class_uid, do: @implementation_class_uid
  def implementation_version_name, do: @implementation_version_name

  def specific_character_set, do: @specific_character_set
  def image_type, do: @image_type
  def sop_class_uid, do: @sop_class_uid
  def sop_instance_uid, do: @sop_instance_uid
  def study_date, do: @study_date
  def series_date, do: @series_date
  def acquisition_date, do: @acquisition_date
  def content_date, do: @content_date
  def study_time, do: @study_time
  def modality, do: @modality

  def patient_name, do: @patient_name
  def patient_id, do: @patient_id
  def patient_birth_date, do: @patient_birth_date
  def patient_sex, do: @patient_sex

  def study_instance_uid, do: @study_instance_uid
  def series_instance_uid, do: @series_instance_uid
  def study_id, do: @study_id
  def series_number, do: @series_number
  def instance_number, do: @instance_number

  def samples_per_pixel, do: @samples_per_pixel
  def photometric_interpretation, do: @photometric_interpretation
  def rows, do: @rows
  def columns, do: @columns
  def bits_allocated, do: @bits_allocated
  def bits_stored, do: @bits_stored
  def high_bit, do: @high_bit
  def pixel_representation, do: @pixel_representation

  def pixel_data, do: @pixel_data

  def item, do: @item
  def item_delimitation_item, do: @item_delimitation_item
  def sequence_delimitation_item, do: @sequence_delimitation_item

  @doc """
  Creates a tag from group and element numbers.

  ## Examples

      iex> Dcmix.Tag.new(0x0010, 0x0010)
      {0x0010, 0x0010}
  """
  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(group, element) when is_integer(group) and is_integer(element) do
    {group, element}
  end

  @doc """
  Parses a tag from a string in format "(GGGG,EEEE)" or "GGGGEEEE".

  ## Examples

      iex> Dcmix.Tag.parse("(0010,0010)")
      {:ok, {0x0010, 0x0010}}

      iex> Dcmix.Tag.parse("00100010")
      {:ok, {0x0010, 0x0010}}
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(string) when is_binary(string) do
    string = String.trim(string)

    cond do
      # Format: (GGGG,EEEE)
      String.match?(string, ~r/^\([0-9A-Fa-f]{4},[0-9A-Fa-f]{4}\)$/) ->
        [group, element] =
          string
          |> String.slice(1..-2//1)
          |> String.split(",")
          |> Enum.map(&String.to_integer(&1, 16))

        {:ok, {group, element}}

      # Format: GGGGEEEE
      String.match?(string, ~r/^[0-9A-Fa-f]{8}$/) ->
        group = String.slice(string, 0..3) |> String.to_integer(16)
        element = String.slice(string, 4..7) |> String.to_integer(16)
        {:ok, {group, element}}

      true ->
        {:error, "Invalid tag format: #{string}"}
    end
  end

  @doc """
  Formats a tag as a string "(GGGG,EEEE)".

  ## Examples

      iex> Dcmix.Tag.to_string({0x0010, 0x0010})
      "(0010,0010)"
  """
  @spec to_string(t()) :: String.t()
  def to_string({group, element}) do
    group_hex = group |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()

    element_hex =
      element |> Integer.to_string(16) |> String.pad_leading(4, "0") |> String.upcase()

    "(#{group_hex},#{element_hex})"
  end

  @doc """
  Returns the group number of a tag.
  """
  @spec group(t()) :: non_neg_integer()
  def group({g, _e}), do: g

  @doc """
  Returns the element number of a tag.
  """
  @spec element(t()) :: non_neg_integer()
  def element({_g, e}), do: e

  @doc """
  Returns true if the tag is in the file meta information group (0002).
  """
  @spec file_meta?(t()) :: boolean()
  def file_meta?({0x0002, _}), do: true
  def file_meta?(_), do: false

  @doc """
  Returns true if the tag is a private tag (odd group number).
  """
  @spec private?(t()) :: boolean()
  def private?({group, _}) when rem(group, 2) == 1 and group > 0x0008, do: true
  def private?(_), do: false

  @doc """
  Returns true if the tag is a group length tag (element 0x0000).
  """
  @spec group_length?(t()) :: boolean()
  def group_length?({_, 0x0000}), do: true
  def group_length?(_), do: false

  @doc """
  Returns true if the tag is an item or delimiter tag.
  """
  @spec item_tag?(t()) :: boolean()
  def item_tag?({0xFFFE, _}), do: true
  def item_tag?(_), do: false

  @doc """
  Compares two tags for ordering. Returns :lt, :eq, or :gt.
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare({g1, e1}, {g2, e2}) do
    cond do
      g1 < g2 -> :lt
      g1 > g2 -> :gt
      e1 < e2 -> :lt
      e1 > e2 -> :gt
      true -> :eq
    end
  end
end
