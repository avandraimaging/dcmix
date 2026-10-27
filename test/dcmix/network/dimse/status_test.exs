defmodule Dcmix.Network.DIMSE.StatusTest do
  use ExUnit.Case, async: true

  require Dcmix.Network.DIMSE.Status, as: Status

  doctest Dcmix.Network.DIMSE.Status

  describe "describe/1" do
    test "names each status dcmix has a macro for" do
      assert Status.describe(Status.success()) == "Success"
      assert Status.describe(Status.pending()) == "Pending"
      assert Status.describe(Status.cancel()) == "Cancel"

      assert Status.describe(Status.sop_class_not_supported()) ==
               "Refused: SOP Class not supported"

      assert Status.describe(Status.out_of_resources()) == "Refused: Out of Resources"

      assert Status.describe(Status.move_destination_unknown()) ==
               "Refused: Move Destination unknown"

      assert Status.describe(Status.cannot_understand()) ==
               "Error: Cannot understand, or Unable to process"

      assert Status.describe(Status.sub_operations_complete_with_failures()) ==
               "Warning: Sub-operations complete, one or more failures or warnings"
    end

    test "names a code within a range the standard defines by its range" do
      assert Status.describe(0xA7FF) == "Refused: Out of Resources"
      assert Status.describe(0xA9FF) == "Error: Data Set or Identifier does not match SOP Class"
      assert Status.describe(0xCFFF) == "Error: Cannot understand, or Unable to process"
    end

    test "names a code with its own meaning in a range by that meaning" do
      assert Status.describe(0xA702) ==
               "Refused: Out of Resources, Unable to perform sub-operations"
    end

    test "says a code it doesn't know is unknown" do
      assert Status.describe(0x1234) == "Unknown status"
    end
  end
end
