defmodule Dcmix.Network.PDUTest do
  use ExUnit.Case, async: true

  alias Dcmix.Network.PDU

  @implicit_vr_le "1.2.840.10008.1.2"
  @explicit_vr_le "1.2.840.10008.1.2.1"
  @study_root_qr_find "1.2.840.10008.5.1.4.1.2.2.1"

  describe "encode_associate_rq/4" do
    test "produces valid PDU with correct type byte" do
      pdu = PDU.encode_associate_rq("CALLING", "CALLED", [])
      assert <<0x01, 0x00, _length::32-big, _rest::binary>> = pdu
    end

    test "pads AE titles to 16 bytes" do
      pdu = PDU.encode_associate_rq("A", "B", [])
      <<0x01, 0x00, _len::32-big, _version::16, _reserved::16, called::binary-size(16),
        calling::binary-size(16), _rest::binary>> = pdu

      assert called == String.pad_trailing("B", 16, " ")
      assert calling == String.pad_trailing("A", 16, " ")
    end

    test "truncates long AE titles to 16 bytes" do
      long_ae = String.duplicate("X", 20)
      pdu = PDU.encode_associate_rq(long_ae, long_ae, [])

      <<0x01, 0x00, _len::32-big, _version::16, _reserved::16, called::binary-size(16),
        calling::binary-size(16), _rest::binary>> = pdu

      assert byte_size(called) == 16
      assert byte_size(calling) == 16
    end

    test "includes presentation context with abstract and transfer syntaxes" do
      contexts = [
        %{
          id: 1,
          abstract_syntax: @study_root_qr_find,
          transfer_syntaxes: [@implicit_vr_le, @explicit_vr_le]
        }
      ]

      pdu = PDU.encode_associate_rq("SCU", "SCP", contexts)
      # Should contain the abstract syntax UID somewhere in the binary
      assert :binary.match(pdu, @study_root_qr_find) != :nomatch
      assert :binary.match(pdu, @implicit_vr_le) != :nomatch
      assert :binary.match(pdu, @explicit_vr_le) != :nomatch
    end

    test "includes application context UID" do
      pdu = PDU.encode_associate_rq("SCU", "SCP", [])
      assert :binary.match(pdu, "1.2.840.10008.3.1.1.1") != :nomatch
    end

    test "includes user information with max PDU length" do
      pdu = PDU.encode_associate_rq("SCU", "SCP", [], max_pdu_length: 32_768)
      # The max PDU length (32768) should appear as a 32-bit big-endian value
      assert :binary.match(pdu, <<32_768::32-big>>) != :nomatch
    end

    test "PDU length field matches actual payload size" do
      pdu = PDU.encode_associate_rq("SCU", "SCP", [])
      <<0x01, 0x00, length::32-big, payload::binary>> = pdu
      assert length == byte_size(payload)
    end
  end

  describe "encode_p_data/4" do
    test "encodes command PDV with correct control header bits" do
      pdu = PDU.encode_p_data(1, true, true, <<1, 2, 3>>)
      # Type 0x04, reserved, length, then PDV
      <<0x04, 0x00, _pdu_len::32-big, _pdv_len::32-big, 1, control::8, 1, 2, 3>> = pdu
      # Command bit (0x01) + Last bit (0x02) = 0x03
      assert control == 0x03
    end

    test "encodes data PDV with correct control header bits" do
      pdu = PDU.encode_p_data(1, false, true, <<4, 5, 6>>)
      <<0x04, 0x00, _pdu_len::32-big, _pdv_len::32-big, 1, control::8, 4, 5, 6>> = pdu
      # Data (not command) + Last = 0x02
      assert control == 0x02
    end

    test "encodes non-last fragment with correct control header" do
      pdu = PDU.encode_p_data(3, true, false, <<7>>)
      <<0x04, 0x00, _pdu_len::32-big, _pdv_len::32-big, 3, control::8, 7>> = pdu
      # Command + not last = 0x01
      assert control == 0x01
    end

    test "preserves presentation context ID" do
      pdu = PDU.encode_p_data(42, false, true, <<>>)
      <<0x04, 0x00, _pdu_len::32-big, _pdv_len::32-big, context_id::8, _::8>> = pdu
      assert context_id == 42
    end

    test "PDU length matches payload" do
      data = :crypto.strong_rand_bytes(100)
      pdu = PDU.encode_p_data(1, true, true, data)
      <<0x04, 0x00, pdu_len::32-big, payload::binary>> = pdu
      assert pdu_len == byte_size(payload)
    end
  end

  describe "encode_release_rq/0" do
    test "produces 10-byte PDU" do
      pdu = PDU.encode_release_rq()
      assert byte_size(pdu) == 10
      assert <<0x05, 0x00, 4::32-big, 0::32>> = pdu
    end
  end

  describe "encode_abort/2" do
    test "produces correct abort PDU" do
      pdu = PDU.encode_abort()
      assert <<0x07, 0x00, 4::32-big, 0x00, 0x00, 0, 0>> = pdu
    end

    test "encodes source and reason" do
      pdu = PDU.encode_abort(2, 6)
      assert <<0x07, 0x00, 4::32-big, 0x00, 0x00, 2, 6>> = pdu
    end
  end

  describe "decode_pdu/1 - P-DATA-TF" do
    test "round-trips P-DATA encoding" do
      original_data = <<10, 20, 30, 40, 50>>
      encoded = PDU.encode_p_data(5, true, true, original_data)

      assert {:ok, {:p_data, [pdv]}, <<>>} = PDU.decode_pdu(encoded)
      assert pdv.context_id == 5
      assert pdv.is_command == true
      assert pdv.is_last == true
      assert pdv.data == original_data
    end

    test "decodes data (non-command) PDV" do
      encoded = PDU.encode_p_data(7, false, true, <<1, 2>>)
      assert {:ok, {:p_data, [pdv]}, <<>>} = PDU.decode_pdu(encoded)
      assert pdv.is_command == false
      assert pdv.is_last == true
    end

    test "decodes non-last fragment PDV" do
      encoded = PDU.encode_p_data(1, true, false, <<99>>)
      assert {:ok, {:p_data, [pdv]}, <<>>} = PDU.decode_pdu(encoded)
      assert pdv.is_last == false
    end
  end

  describe "decode_pdu/1 - A-RELEASE" do
    test "decodes release RP" do
      release_rp = <<0x06, 0x00, 4::32-big, 0::32>>
      assert {:ok, :release_rp, <<>>} = PDU.decode_pdu(release_rp)
    end

    test "decodes release RQ" do
      release_rq = PDU.encode_release_rq()
      assert {:ok, :release_rq, <<>>} = PDU.decode_pdu(release_rq)
    end
  end

  describe "decode_pdu/1 - A-ABORT" do
    test "decodes abort" do
      abort = PDU.encode_abort(2, 3)
      assert {:ok, {:abort, %{source: 2, reason: 3}}, <<>>} = PDU.decode_pdu(abort)
    end
  end

  describe "decode_pdu/1 - A-ASSOCIATE-RJ" do
    test "decodes association rejection" do
      reject = <<0x03, 0x00, 4::32-big, 0x00, 0x00, 1, 2>>
      assert {:ok, {:associate_rj, %{result: 1, reason: 2}}, <<>>} = PDU.decode_pdu(reject)
    end
  end

  describe "decode_pdu/1 - A-ASSOCIATE-AC" do
    test "decodes a well-formed A-ASSOCIATE-AC" do
      # Build a minimal A-ASSOCIATE-AC
      called_ae = String.pad_trailing("SCP", 16, " ")
      calling_ae = String.pad_trailing("SCU", 16, " ")

      # Transfer syntax sub-item
      ts_uid = @implicit_vr_le
      ts_item = <<0x40, 0x00, byte_size(ts_uid)::16-big, ts_uid::binary>>

      # Presentation context result item (accepted)
      pc_content = <<1, 0x00, 0, 0x00, ts_item::binary>>
      pc_item = <<0x21, 0x00, byte_size(pc_content)::16-big, pc_content::binary>>

      # Max length sub-item
      max_length_sub = <<0x51, 0x00, 4::16-big, 65_536::32-big>>
      user_info_content = max_length_sub
      user_info = <<0x50, 0x00, byte_size(user_info_content)::16-big, user_info_content::binary>>

      payload =
        IO.iodata_to_binary([
          <<1::16-big>>,
          <<0::16>>,
          called_ae,
          calling_ae,
          <<0::256>>,
          pc_item,
          user_info
        ])

      pdu = <<0x02, 0x00, byte_size(payload)::32-big, payload::binary>>

      assert {:ok, {:associate_ac, result}, <<>>} = PDU.decode_pdu(pdu)
      assert result.called_ae_title == "SCP"
      assert result.calling_ae_title == "SCU"
      assert result.max_pdu_length == 65_536
      assert [%{id: 1, result: 0, transfer_syntax: @implicit_vr_le}] = result.presentation_contexts
    end
  end

  describe "decode_pdu/1 - errors" do
    test "returns error for incomplete header" do
      assert {:error, :incomplete_header} = PDU.decode_pdu(<<1, 2>>)
    end

    test "returns error for incomplete payload" do
      assert {:error, {:incomplete_pdu, 100, 2}} =
               PDU.decode_pdu(<<0x04, 0x00, 100::32-big, 0x00, 0x00>>)
    end
  end

  describe "decode_header/1" do
    test "decodes 6-byte header" do
      assert {:ok, 0x04, 256} = PDU.decode_header(<<0x04, 0x00, 256::32-big>>)
    end

    test "returns error for short data" do
      assert {:error, :incomplete_header} = PDU.decode_header(<<1, 2, 3>>)
    end
  end

  describe "remaining data handling" do
    test "returns remaining bytes after PDU" do
      pdu = PDU.encode_release_rq()
      extra = <<0xFF, 0xFE>>

      assert {:ok, :release_rq, ^extra} = PDU.decode_pdu(pdu <> extra)
    end
  end
end
