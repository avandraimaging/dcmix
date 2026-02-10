defmodule Dcmix.Network.DIMSE do
  @moduledoc """
  DICOM Message Service Element (DIMSE) command encoding and decoding.

  Handles the construction and parsing of DICOM command datasets
  (group 0000 elements). Command datasets are always encoded as
  Implicit VR Little Endian per the DICOM standard.

  Currently supports:
  - C-FIND-RQ command building
  - Response status parsing
  """

  # Command tags (group 0000, not in data dictionary)
  @command_group_length {0x0000, 0x0000}
  @affected_sop_class_uid {0x0000, 0x0002}
  @command_field {0x0000, 0x0100}
  @message_id {0x0000, 0x0110}
  @priority {0x0000, 0x0700}
  @command_data_set_type {0x0000, 0x0800}
  @status {0x0000, 0x0900}

  # Command field values
  @cfind_rq 0x0020

  # Priority values
  @priority_medium 0x0000

  # Data set type values
  @dataset_present 0x0001

  @doc """
  Builds a C-FIND-RQ command as encoded binary (Implicit VR Little Endian).

  The binary includes the Command Group Length element (0000,0000) followed
  by all other command elements.

  ## Parameters
  - `sop_class_uid` - The abstract syntax UID (e.g., Study Root Q/R Find)
  - `message_id` - Message ID (typically 1)
  """
  @spec build_cfind_rq(String.t(), non_neg_integer()) :: binary()
  def build_cfind_rq(sop_class_uid, message_id) do
    # Build each command element as Implicit VR LE binary
    # Format: tag(4) + length(4) + value
    elements =
      IO.iodata_to_binary([
        encode_ui_element(@affected_sop_class_uid, sop_class_uid),
        encode_us_element(@command_field, @cfind_rq),
        encode_us_element(@message_id, message_id),
        encode_us_element(@priority, @priority_medium),
        encode_us_element(@command_data_set_type, @dataset_present)
      ])

    # Prepend group length: (0000,0000) UL = byte_size(elements)
    group_length = encode_ul_element(@command_group_length, byte_size(elements))

    group_length <> elements
  end

  @doc """
  Parses the status code from a response command dataset binary.

  The command is encoded as Implicit VR Little Endian. We scan for
  the Status tag (0000,0900) and extract its US value.
  """
  @spec parse_status(binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def parse_status(command_binary) do
    find_tag_value(command_binary, @status)
  end

  @doc """
  Returns true if the status code indicates a pending response (more data follows).
  """
  @spec status_pending?(non_neg_integer()) :: boolean()
  def status_pending?(0xFF00), do: true
  def status_pending?(0xFF01), do: true
  def status_pending?(_), do: false

  @doc """
  Returns true if the status code indicates success (operation complete).
  """
  @spec status_success?(non_neg_integer()) :: boolean()
  def status_success?(0x0000), do: true
  def status_success?(_), do: false

  @doc """
  Classifies a status code into a category.
  """
  @spec status_meaning(non_neg_integer()) :: :success | :pending | :cancel | :failure
  def status_meaning(0x0000), do: :success
  def status_meaning(0xFF00), do: :pending
  def status_meaning(0xFF01), do: :pending
  def status_meaning(0xFE00), do: :cancel
  def status_meaning(_), do: :failure

  # ===========================================================================
  # Implicit VR Little Endian element encoding
  # ===========================================================================

  defp encode_ui_element(tag, value) do
    # UI values must be even-length (pad with null byte if needed)
    padded =
      if rem(byte_size(value), 2) == 1 do
        value <> <<0>>
      else
        value
      end

    encode_raw_element(tag, padded)
  end

  defp encode_us_element(tag, value) do
    encode_raw_element(tag, <<value::16-little>>)
  end

  defp encode_ul_element(tag, value) do
    encode_raw_element(tag, <<value::32-little>>)
  end

  defp encode_raw_element({group, element}, value_bytes) do
    <<group::16-little, element::16-little, byte_size(value_bytes)::32-little,
      value_bytes::binary>>
  end

  # ===========================================================================
  # Scanning for a tag value in Implicit VR LE command data
  # ===========================================================================

  defp find_tag_value(<<>>, target_tag) do
    {:error, {:tag_not_found, target_tag}}
  end

  defp find_tag_value(
         <<group::16-little, element::16-little, length::32-little, rest::binary>>,
         {target_group, target_element} = target_tag
       ) do
    if group == target_group and element == target_element do
      extract_us_value(rest, length)
    else
      if byte_size(rest) >= length do
        <<_value::binary-size(length), remaining::binary>> = rest
        find_tag_value(remaining, target_tag)
      else
        {:error, :unexpected_eof}
      end
    end
  end

  defp find_tag_value(_, _), do: {:error, :parse_error}

  defp extract_us_value(<<value::16-little, _rest::binary>>, _length) do
    {:ok, value}
  end

  defp extract_us_value(_, _), do: {:error, :invalid_status_value}
end
