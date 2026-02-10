defmodule Dcmix.Network.DIMSETest do
  use ExUnit.Case, async: true

  alias Dcmix.Network.DIMSE

  @study_root_qr_find "1.2.840.10008.5.1.4.1.2.2.1"

  describe "build_cfind_rq/2" do
    test "starts with group length element (0000,0000)" do
      binary = DIMSE.build_cfind_rq(@study_root_qr_find, 1)

      assert <<0x0000::16-little, 0x0000::16-little, 4::32-little, _group_length::32-little,
               _rest::binary>> = binary
    end

    test "group length value matches remaining bytes" do
      binary = DIMSE.build_cfind_rq(@study_root_qr_find, 1)

      <<0x0000::16-little, 0x0000::16-little, 4::32-little, group_length::32-little,
        rest::binary>> = binary

      assert group_length == byte_size(rest)
    end

    test "contains Affected SOP Class UID (0000,0002)" do
      binary = DIMSE.build_cfind_rq(@study_root_qr_find, 1)
      assert :binary.match(binary, @study_root_qr_find) != :nomatch
    end

    test "contains Command Field = 0x0020 (C-FIND-RQ)" do
      binary = DIMSE.build_cfind_rq(@study_root_qr_find, 1)
      # Tag (0000,0100) in Implicit VR LE: group LE, element LE, length LE, value LE
      pattern = <<0x0000::16-little, 0x0100::16-little, 2::32-little, 0x0020::16-little>>
      assert :binary.match(binary, pattern) != :nomatch
    end

    test "contains Message ID" do
      binary = DIMSE.build_cfind_rq(@study_root_qr_find, 42)
      pattern = <<0x0000::16-little, 0x0110::16-little, 2::32-little, 42::16-little>>
      assert :binary.match(binary, pattern) != :nomatch
    end

    test "contains Priority = Medium (0x0000)" do
      binary = DIMSE.build_cfind_rq(@study_root_qr_find, 1)
      pattern = <<0x0000::16-little, 0x0700::16-little, 2::32-little, 0x0000::16-little>>
      assert :binary.match(binary, pattern) != :nomatch
    end

    test "contains Command Data Set Type = Present (0x0001)" do
      binary = DIMSE.build_cfind_rq(@study_root_qr_find, 1)
      pattern = <<0x0000::16-little, 0x0800::16-little, 2::32-little, 0x0001::16-little>>
      assert :binary.match(binary, pattern) != :nomatch
    end

    test "UID with odd length is null-padded to even" do
      odd_uid = "1.2.3"
      assert rem(byte_size(odd_uid), 2) == 1

      binary = DIMSE.build_cfind_rq(odd_uid, 1)
      assert :binary.match(binary, odd_uid <> <<0>>) != :nomatch
    end
  end

  describe "parse_status/1" do
    test "extracts success status from command response" do
      response = build_status_response(0x0000)
      assert {:ok, 0x0000} = DIMSE.parse_status(response)
    end

    test "extracts pending status 0xFF00" do
      response = build_status_response(0xFF00)
      assert {:ok, 0xFF00} = DIMSE.parse_status(response)
    end

    test "extracts pending status 0xFF01" do
      response = build_status_response(0xFF01)
      assert {:ok, 0xFF01} = DIMSE.parse_status(response)
    end

    test "extracts failure status 0xA700" do
      response = build_status_response(0xA700)
      assert {:ok, 0xA700} = DIMSE.parse_status(response)
    end

    test "returns error when status tag not found" do
      # Just a group length element, no status tag
      binary =
        <<0x0000::16-little, 0x0000::16-little, 4::32-little, 100::32-little>>

      assert {:error, {:tag_not_found, {0x0000, 0x0900}}} = DIMSE.parse_status(binary)
    end

    test "handles command with multiple elements before status" do
      elements =
        IO.iodata_to_binary([
          # Group length (0000,0000)
          <<0x0000::16-little, 0x0000::16-little, 4::32-little, 50::32-little>>,
          # Affected SOP Class UID (0000,0002)
          <<0x0000::16-little, 0x0002::16-little, 4::32-little, "1.2."::binary>>,
          # Command Field (0000,0100)
          <<0x0000::16-little, 0x0100::16-little, 2::32-little, 0x8020::16-little>>,
          # Status (0000,0900)
          <<0x0000::16-little, 0x0900::16-little, 2::32-little, 0xFF00::16-little>>
        ])

      assert {:ok, 0xFF00} = DIMSE.parse_status(elements)
    end
  end

  describe "status_pending?/1" do
    test "0xFF00 is pending" do
      assert DIMSE.status_pending?(0xFF00)
    end

    test "0xFF01 is pending" do
      assert DIMSE.status_pending?(0xFF01)
    end

    test "0x0000 is not pending" do
      refute DIMSE.status_pending?(0x0000)
    end

    test "failure codes are not pending" do
      refute DIMSE.status_pending?(0xA700)
      refute DIMSE.status_pending?(0xC000)
    end
  end

  describe "status_success?/1" do
    test "0x0000 is success" do
      assert DIMSE.status_success?(0x0000)
    end

    test "0xFF00 is not success" do
      refute DIMSE.status_success?(0xFF00)
    end
  end

  describe "status_meaning/1" do
    test "classifies status codes" do
      assert :success == DIMSE.status_meaning(0x0000)
      assert :pending == DIMSE.status_meaning(0xFF00)
      assert :pending == DIMSE.status_meaning(0xFF01)
      assert :cancel == DIMSE.status_meaning(0xFE00)
      assert :failure == DIMSE.status_meaning(0xA700)
      assert :failure == DIMSE.status_meaning(0xC000)
      assert :failure == DIMSE.status_meaning(0x0122)
    end
  end

  # Helper to build a minimal command response with a status element
  defp build_status_response(status_code) do
    IO.iodata_to_binary([
      # Group length (0000,0000) - dummy value
      <<0x0000::16-little, 0x0000::16-little, 4::32-little, 10::32-little>>,
      # Status (0000,0900)
      <<0x0000::16-little, 0x0900::16-little, 2::32-little, status_code::16-little>>
    ])
  end
end
