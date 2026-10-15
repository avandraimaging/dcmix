defmodule Dcmix.Network.ConstantsTest do
  use ExUnit.Case, async: true

  alias Dcmix.Network.SOPClassUID

  require Dcmix.Network.DIMSE.CommandField, as: CommandField

  test "Verification SOP Class UID matches PS3.4" do
    assert SOPClassUID.verification() == "1.2.840.10008.1.1"
  end

  test "C-ECHO command fields match PS3.7 E.1" do
    assert CommandField.c_echo_rq() == 0x0030
    assert CommandField.c_echo_rsp() == 0x8030
  end

  test "command fields work in patterns" do
    assert match?(%{command_field: CommandField.c_echo_rsp()}, %{command_field: 0x8030})
  end
end
