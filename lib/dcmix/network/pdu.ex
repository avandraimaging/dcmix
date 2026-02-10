defmodule Dcmix.Network.PDU do
  @moduledoc """
  DICOM Upper Layer PDU (Protocol Data Unit) encoding and decoding.

  Implements the binary wire format for DICOM network communication
  as defined in DICOM Part 8. This module handles only serialization
  and deserialization — no TCP or state management.

  ## PDU Types

  | Code | Type           | Direction      |
  |------|----------------|----------------|
  | 0x01 | A-ASSOCIATE-RQ | Encode (send)  |
  | 0x02 | A-ASSOCIATE-AC | Decode (recv)  |
  | 0x03 | A-ASSOCIATE-RJ | Decode (recv)  |
  | 0x04 | P-DATA-TF      | Both           |
  | 0x05 | A-RELEASE-RQ   | Encode (send)  |
  | 0x06 | A-RELEASE-RP   | Decode (recv)  |
  | 0x07 | A-ABORT        | Both           |
  """

  # PDU type codes
  @associate_rq 0x01
  @associate_ac 0x02
  @associate_rj 0x03
  @p_data_tf 0x04
  @release_rq 0x05
  @release_rp 0x06
  @abort 0x07

  # Sub-item type codes
  @application_context_item 0x10
  @presentation_context_rq_item 0x20
  @presentation_context_ac_item 0x21
  @abstract_syntax_item 0x30
  @transfer_syntax_item 0x40
  @user_information_item 0x50
  @max_length_item 0x51
  @implementation_class_uid_item 0x52
  @implementation_version_name_item 0x55

  # Standard UIDs
  @application_context_uid "1.2.840.10008.3.1.1.1"
  @implementation_class_uid "1.2.826.0.1.3680043.8.1234.1"
  @implementation_version_name "DCMIX_010"

  # Default max PDU length (16KB, conservative for wide compatibility)
  @default_max_pdu_length 16_384

  # Protocol version
  @protocol_version 1

  @type presentation_context :: %{
          id: non_neg_integer(),
          abstract_syntax: String.t(),
          transfer_syntaxes: [String.t()]
        }

  @type accepted_context :: %{
          id: non_neg_integer(),
          result: non_neg_integer(),
          transfer_syntax: String.t()
        }

  @type pdv :: %{
          context_id: non_neg_integer(),
          is_command: boolean(),
          is_last: boolean(),
          data: binary()
        }

  @type pdu ::
          {:associate_rq, map()}
          | {:associate_ac, map()}
          | {:associate_rj, map()}
          | {:p_data, [pdv()]}
          | :release_rq
          | :release_rp
          | {:abort, map()}

  # ===========================================================================
  # Encoding
  # ===========================================================================

  @doc """
  Encodes an A-ASSOCIATE-RQ PDU.

  ## Parameters
  - `calling_ae` - Calling AE Title (will be padded/truncated to 16 bytes)
  - `called_ae` - Called AE Title (will be padded/truncated to 16 bytes)
  - `presentation_contexts` - List of presentation context maps
  - `opts` - Options:
    - `:max_pdu_length` - Maximum PDU length to propose (default: 16384)
  """
  @spec encode_associate_rq(String.t(), String.t(), [presentation_context()], keyword()) ::
          binary()
  def encode_associate_rq(calling_ae, called_ae, presentation_contexts, opts \\ []) do
    max_pdu_length = Keyword.get(opts, :max_pdu_length, @default_max_pdu_length)

    payload =
      IO.iodata_to_binary([
        # Protocol version
        <<@protocol_version::16-big>>,
        # Reserved
        <<0::16>>,
        # Called AE Title (16 bytes, space-padded)
        pad_ae_title(called_ae),
        # Calling AE Title (16 bytes, space-padded)
        pad_ae_title(calling_ae),
        # Reserved (32 bytes)
        <<0::256>>,
        # Application Context Item
        encode_application_context(),
        # Presentation Context Items
        Enum.map(presentation_contexts, &encode_presentation_context_rq/1),
        # User Information Item
        encode_user_information(max_pdu_length)
      ])

    <<@associate_rq, 0x00, byte_size(payload)::32-big, payload::binary>>
  end

  @doc """
  Encodes a P-DATA-TF PDU containing one PDV item.
  """
  @spec encode_p_data(non_neg_integer(), boolean(), boolean(), binary()) :: binary()
  def encode_p_data(context_id, is_command, is_last, data) do
    control_header = encode_control_header(is_command, is_last)

    # PDV item: length(4) + context_id(1) + control_header(1) + data
    pdv_length = 1 + 1 + byte_size(data)

    pdv_item =
      <<pdv_length::32-big, context_id::8, control_header::8, data::binary>>

    <<@p_data_tf, 0x00, byte_size(pdv_item)::32-big, pdv_item::binary>>
  end

  @doc """
  Encodes an A-RELEASE-RQ PDU.
  """
  @spec encode_release_rq() :: binary()
  def encode_release_rq do
    <<@release_rq, 0x00, 4::32-big, 0::32>>
  end

  @doc """
  Encodes an A-ABORT PDU.
  """
  @spec encode_abort(non_neg_integer(), non_neg_integer()) :: binary()
  def encode_abort(source \\ 0, reason \\ 0) do
    <<@abort, 0x00, 4::32-big, 0x00, 0x00, source::8, reason::8>>
  end

  # ===========================================================================
  # Decoding
  # ===========================================================================

  @doc """
  Decodes a PDU from binary data.

  Returns `{:ok, pdu, rest}` where `pdu` is a tagged tuple and `rest`
  is any remaining data after the PDU.
  """
  @spec decode_pdu(binary()) :: {:ok, pdu(), binary()} | {:error, term()}
  def decode_pdu(<<type::8, _reserved::8, length::32-big, rest::binary>>)
      when byte_size(rest) >= length do
    <<payload::binary-size(length), remaining::binary>> = rest
    decode_pdu_payload(type, payload, remaining)
  end

  def decode_pdu(<<_type::8, _reserved::8, length::32-big, rest::binary>>)
      when byte_size(rest) < length do
    {:error, {:incomplete_pdu, length, byte_size(rest)}}
  end

  def decode_pdu(data) when byte_size(data) < 6 do
    {:error, :incomplete_header}
  end

  def decode_pdu(_) do
    {:error, :invalid_pdu}
  end

  defp decode_pdu_payload(@associate_ac, payload, rest) do
    case decode_associate_ac_payload(payload) do
      {:ok, result} -> {:ok, {:associate_ac, result}, rest}
      {:error, _} = error -> error
    end
  end

  defp decode_pdu_payload(@associate_rj, <<_::8, _::8, result::8, reason::8>>, rest) do
    {:ok, {:associate_rj, %{result: result, reason: reason}}, rest}
  end

  defp decode_pdu_payload(@p_data_tf, payload, rest) do
    case decode_pdv_items(payload, []) do
      {:ok, pdvs} -> {:ok, {:p_data, pdvs}, rest}
      {:error, _} = error -> error
    end
  end

  defp decode_pdu_payload(@release_rq, _payload, rest) do
    {:ok, :release_rq, rest}
  end

  defp decode_pdu_payload(@release_rp, _payload, rest) do
    {:ok, :release_rp, rest}
  end

  defp decode_pdu_payload(@abort, <<_::8, _::8, source::8, reason::8>>, rest) do
    {:ok, {:abort, %{source: source, reason: reason}}, rest}
  end

  defp decode_pdu_payload(@abort, _payload, rest) do
    {:ok, {:abort, %{source: 0, reason: 0}}, rest}
  end

  defp decode_pdu_payload(type, _payload, _rest) do
    {:error, {:unknown_pdu_type, type}}
  end

  # ===========================================================================
  # A-ASSOCIATE-AC Decoding
  # ===========================================================================

  defp decode_associate_ac_payload(
         <<_protocol_version::16-big, _reserved::16, called_ae::binary-size(16),
           calling_ae::binary-size(16), _reserved2::binary-size(32),
           variable_items::binary>>
       ) do
    case decode_variable_items(variable_items, %{presentation_contexts: [], max_pdu_length: @default_max_pdu_length}) do
      {:ok, items} ->
        {:ok,
         %{
           called_ae_title: String.trim(called_ae),
           calling_ae_title: String.trim(calling_ae),
           presentation_contexts: items.presentation_contexts,
           max_pdu_length: items.max_pdu_length
         }}

      {:error, _} = error ->
        error
    end
  end

  defp decode_associate_ac_payload(_), do: {:error, :invalid_associate_ac}

  defp decode_variable_items(<<>>, acc), do: {:ok, acc}

  defp decode_variable_items(
         <<@presentation_context_ac_item, _reserved::8, length::16-big, rest::binary>>,
         acc
       )
       when byte_size(rest) >= length do
    <<item_data::binary-size(length), remaining::binary>> = rest

    case decode_presentation_context_ac(item_data) do
      {:ok, pc} ->
        updated = %{acc | presentation_contexts: acc.presentation_contexts ++ [pc]}
        decode_variable_items(remaining, updated)

      {:error, _} = error ->
        error
    end
  end

  defp decode_variable_items(
         <<@user_information_item, _reserved::8, length::16-big, rest::binary>>,
         acc
       )
       when byte_size(rest) >= length do
    <<item_data::binary-size(length), remaining::binary>> = rest

    case decode_user_information(item_data, acc) do
      {:ok, updated} -> decode_variable_items(remaining, updated)
      {:error, _} = error -> error
    end
  end

  defp decode_variable_items(
         <<_type::8, _reserved::8, length::16-big, rest::binary>>,
         acc
       )
       when byte_size(rest) >= length do
    # Skip unknown items
    <<_item_data::binary-size(length), remaining::binary>> = rest
    decode_variable_items(remaining, acc)
  end

  defp decode_variable_items(<<>>, acc), do: {:ok, acc}
  defp decode_variable_items(_, _acc), do: {:error, :invalid_variable_items}

  defp decode_presentation_context_ac(
         <<pc_id::8, _reserved::8, result::8, _reserved2::8, rest::binary>>
       ) do
    transfer_syntax = extract_sub_item_uid(@transfer_syntax_item, rest)

    {:ok,
     %{
       id: pc_id,
       result: result,
       transfer_syntax: transfer_syntax || ""
     }}
  end

  defp decode_presentation_context_ac(_), do: {:error, :invalid_presentation_context}

  defp decode_user_information(<<>>, acc), do: {:ok, acc}

  defp decode_user_information(
         <<@max_length_item, _reserved::8, 4::16-big, max_length::32-big, rest::binary>>,
         acc
       ) do
    decode_user_information(rest, %{acc | max_pdu_length: max_length})
  end

  defp decode_user_information(
         <<_type::8, _reserved::8, length::16-big, rest::binary>>,
         acc
       )
       when byte_size(rest) >= length do
    <<_item::binary-size(length), remaining::binary>> = rest
    decode_user_information(remaining, acc)
  end

  defp decode_user_information(_, acc), do: {:ok, acc}

  # ===========================================================================
  # PDV Decoding
  # ===========================================================================

  defp decode_pdv_items(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_pdv_items(<<pdv_length::32-big, rest::binary>>, acc)
       when byte_size(rest) >= pdv_length do
    <<pdv_data::binary-size(pdv_length), remaining::binary>> = rest

    case decode_single_pdv(pdv_data) do
      {:ok, pdv} -> decode_pdv_items(remaining, [pdv | acc])
      {:error, _} = error -> error
    end
  end

  defp decode_pdv_items(_, _acc), do: {:error, :incomplete_pdv}

  defp decode_single_pdv(<<context_id::8, control_header::8, data::binary>>) do
    is_command = Bitwise.band(control_header, 0x01) == 0x01
    is_last = Bitwise.band(control_header, 0x02) == 0x02

    {:ok,
     %{
       context_id: context_id,
       is_command: is_command,
       is_last: is_last,
       data: data
     }}
  end

  defp decode_single_pdv(_), do: {:error, :invalid_pdv}

  # ===========================================================================
  # Helpers
  # ===========================================================================

  @doc """
  Reads a PDU header (6 bytes) and returns the type and expected length.
  """
  @spec decode_header(binary()) :: {:ok, non_neg_integer(), non_neg_integer()} | {:error, term()}
  def decode_header(<<type::8, _reserved::8, length::32-big>>) do
    {:ok, type, length}
  end

  def decode_header(_), do: {:error, :incomplete_header}

  defp pad_ae_title(ae_title) do
    ae_title
    |> String.slice(0, 16)
    |> String.pad_trailing(16, " ")
  end

  defp encode_control_header(is_command, is_last) do
    cmd_bit = if is_command, do: 0x01, else: 0x00
    last_bit = if is_last, do: 0x02, else: 0x00
    Bitwise.bor(cmd_bit, last_bit)
  end

  defp encode_application_context do
    uid = @application_context_uid
    <<@application_context_item, 0x00, byte_size(uid)::16-big, uid::binary>>
  end

  defp encode_presentation_context_rq(%{
         id: id,
         abstract_syntax: abstract_syntax,
         transfer_syntaxes: transfer_syntaxes
       }) do
    abstract_syntax_item =
      <<@abstract_syntax_item, 0x00, byte_size(abstract_syntax)::16-big,
        abstract_syntax::binary>>

    ts_items =
      Enum.map(transfer_syntaxes, fn ts ->
        <<@transfer_syntax_item, 0x00, byte_size(ts)::16-big, ts::binary>>
      end)

    content = IO.iodata_to_binary([abstract_syntax_item | ts_items])

    # Presentation context: id(1) + reserved(3) + content
    pc_data = <<id::8, 0x00, 0x00, 0x00, content::binary>>
    <<@presentation_context_rq_item, 0x00, byte_size(pc_data)::16-big, pc_data::binary>>
  end

  defp encode_user_information(max_pdu_length) do
    max_length_sub =
      <<@max_length_item, 0x00, 4::16-big, max_pdu_length::32-big>>

    impl_class_uid = @implementation_class_uid

    impl_class_sub =
      <<@implementation_class_uid_item, 0x00, byte_size(impl_class_uid)::16-big,
        impl_class_uid::binary>>

    impl_version = @implementation_version_name

    impl_version_sub =
      <<@implementation_version_name_item, 0x00, byte_size(impl_version)::16-big,
        impl_version::binary>>

    content =
      IO.iodata_to_binary([max_length_sub, impl_class_sub, impl_version_sub])

    <<@user_information_item, 0x00, byte_size(content)::16-big, content::binary>>
  end

  defp extract_sub_item_uid(_type, <<>>), do: nil

  defp extract_sub_item_uid(type, <<type::8, _::8, length::16-big, rest::binary>>)
       when byte_size(rest) >= length do
    <<uid::binary-size(length), _::binary>> = rest
    String.trim_trailing(uid, <<0>>)
  end

  defp extract_sub_item_uid(type, <<_other::8, _::8, length::16-big, rest::binary>>)
       when byte_size(rest) >= length do
    <<_::binary-size(length), remaining::binary>> = rest
    extract_sub_item_uid(type, remaining)
  end

  defp extract_sub_item_uid(_, _), do: nil
end
