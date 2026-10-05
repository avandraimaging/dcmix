defmodule Dcmix.Network.DIMSE do
  @moduledoc """
  DICOM Message Service Element (DIMSE) command encoding and decoding.

  Handles the construction and parsing of DICOM command datasets
  (group 0000 elements). Command datasets are always encoded as
  Implicit VR Little Endian per the DICOM standard.

  Currently supports:
  - C-FIND-RQ, C-GET-RQ, C-CANCEL-RQ and C-STORE-RSP command building
  - Response status parsing and general command decoding
  """

  # Command tags (group 0000, not in data dictionary)
  @command_group_length {0x0000, 0x0000}
  @affected_sop_class_uid {0x0000, 0x0002}
  @command_field {0x0000, 0x0100}
  @message_id {0x0000, 0x0110}
  @message_id_being_responded_to {0x0000, 0x0120}
  @priority {0x0000, 0x0700}
  @command_data_set_type {0x0000, 0x0800}
  @status {0x0000, 0x0900}
  @affected_sop_instance_uid {0x0000, 0x1000}
  @remaining_sub_operations {0x0000, 0x1020}
  @completed_sub_operations {0x0000, 0x1021}
  @failed_sub_operations {0x0000, 0x1022}
  @warning_sub_operations {0x0000, 0x1023}

  # Command field values
  @cstore_rsp 0x8001
  @cget_rq 0x0010
  @cfind_rq 0x0020
  @ccancel_rq 0x0FFF

  # Priority values
  @priority_medium 0x0000

  # Data set type values
  @dataset_present 0x0001
  @no_dataset 0x0101

  @us_tags [
    @command_field,
    @message_id,
    @message_id_being_responded_to,
    @priority,
    @command_data_set_type,
    @status,
    @remaining_sub_operations,
    @completed_sub_operations,
    @failed_sub_operations,
    @warning_sub_operations
  ]

  @ui_tags [@affected_sop_class_uid, @affected_sop_instance_uid]

  @type command :: %{
          command_field: non_neg_integer() | nil,
          message_id: non_neg_integer() | nil,
          message_id_being_responded_to: non_neg_integer() | nil,
          command_data_set_type: non_neg_integer() | nil,
          status: non_neg_integer() | nil,
          affected_sop_class_uid: String.t() | nil,
          affected_sop_instance_uid: String.t() | nil,
          remaining: non_neg_integer() | nil,
          completed: non_neg_integer() | nil,
          failed: non_neg_integer() | nil,
          warning: non_neg_integer() | nil
        }

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
    with_group_length([
      encode_ui_element(@affected_sop_class_uid, sop_class_uid),
      encode_us_element(@command_field, @cfind_rq),
      encode_us_element(@message_id, message_id),
      encode_us_element(@priority, @priority_medium),
      encode_us_element(@command_data_set_type, @dataset_present)
    ])
  end

  @doc """
  Builds a C-GET-RQ command (Implicit VR Little Endian).

  ## Parameters
  - `sop_class_uid` - The Q/R GET SOP Class (Patient or Study Root)
  - `message_id` - Message ID
  - `priority` - `0x0000` medium (default), `0x0001` high, `0x0002` low
  """
  @spec build_cget_rq(String.t(), non_neg_integer(), non_neg_integer()) :: binary()
  def build_cget_rq(sop_class_uid, message_id, priority \\ @priority_medium) do
    with_group_length([
      encode_ui_element(@affected_sop_class_uid, sop_class_uid),
      encode_us_element(@command_field, @cget_rq),
      encode_us_element(@message_id, message_id),
      encode_us_element(@priority, priority),
      encode_us_element(@command_data_set_type, @dataset_present)
    ])
  end

  @doc """
  Builds a C-STORE-RSP command (Implicit VR Little Endian) with no data set.
  """
  @spec build_cstore_rsp(String.t(), String.t(), non_neg_integer(), non_neg_integer()) ::
          binary()
  def build_cstore_rsp(sop_class_uid, sop_instance_uid, message_id_being_responded_to, status) do
    with_group_length([
      encode_ui_element(@affected_sop_class_uid, sop_class_uid),
      encode_us_element(@command_field, @cstore_rsp),
      encode_us_element(@message_id_being_responded_to, message_id_being_responded_to),
      encode_us_element(@command_data_set_type, @no_dataset),
      encode_us_element(@status, status),
      encode_ui_element(@affected_sop_instance_uid, sop_instance_uid)
    ])
  end

  @doc """
  Builds a C-CANCEL-RQ command (Implicit VR Little Endian) for an
  outstanding request.
  """
  @spec build_ccancel_rq(non_neg_integer()) :: binary()
  def build_ccancel_rq(message_id_being_responded_to) do
    with_group_length([
      encode_us_element(@command_field, @ccancel_rq),
      encode_us_element(@message_id_being_responded_to, message_id_being_responded_to),
      encode_us_element(@command_data_set_type, @no_dataset)
    ])
  end

  @doc """
  Decodes a command set (Implicit VR Little Endian) into a map.

  Fields absent from the command are `nil`. The sub-operation counts
  (0000,1020-1023) are returned as `:remaining`, `:completed`, `:failed`
  and `:warning`.
  """
  @spec decode_command(binary()) :: {:ok, command()} | {:error, term()}
  def decode_command(command_binary) do
    with {:ok, values} <- decode_elements(command_binary, %{}) do
      {:ok,
       %{
         command_field: values[@command_field],
         message_id: values[@message_id],
         message_id_being_responded_to: values[@message_id_being_responded_to],
         command_data_set_type: values[@command_data_set_type],
         status: values[@status],
         affected_sop_class_uid: values[@affected_sop_class_uid],
         affected_sop_instance_uid: values[@affected_sop_instance_uid],
         remaining: values[@remaining_sub_operations],
         completed: values[@completed_sub_operations],
         failed: values[@failed_sub_operations],
         warning: values[@warning_sub_operations]
       }}
    end
  end

  @doc """
  Returns true if a command's Command Data Set Type announces a data set.
  """
  @spec dataset_present?(non_neg_integer() | nil) :: boolean()
  def dataset_present?(@no_dataset), do: false
  def dataset_present?(nil), do: false
  def dataset_present?(_), do: true

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

  # Prepends (0000,0000) Command Group Length covering the given elements
  defp with_group_length(elements) do
    elements = IO.iodata_to_binary(elements)
    encode_ul_element(@command_group_length, byte_size(elements)) <> elements
  end

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

  # ===========================================================================
  # General command decoding
  # ===========================================================================

  defp decode_elements(<<>>, acc), do: {:ok, acc}

  defp decode_elements(
         <<group::16-little, element::16-little, length::32-little, rest::binary>>,
         acc
       )
       when byte_size(rest) >= length do
    <<value::binary-size(length), remaining::binary>> = rest
    decode_elements(remaining, put_command_value(acc, {group, element}, value))
  end

  defp decode_elements(_, _acc), do: {:error, :invalid_command}

  defp put_command_value(acc, tag, <<value::16-little, _::binary>>) when tag in @us_tags,
    do: Map.put(acc, tag, value)

  defp put_command_value(acc, tag, value) when tag in @ui_tags,
    do: Map.put(acc, tag, String.trim_trailing(value, <<0>>))

  defp put_command_value(acc, _tag, _value), do: acc
end
