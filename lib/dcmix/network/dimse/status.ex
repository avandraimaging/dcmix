defmodule Dcmix.Network.DIMSE.Status do
  @moduledoc """
  DIMSE Status (0000,0900) codes (PS3.4, PS3.7 Annex C).

  These are macros so they can be used in patterns and guards as well as
  expressions; `require Dcmix.Network.DIMSE.Status` before use.
  `describe/1` names any code in words.
  """

  # Codes with a meaning of their own, from PS3.7 Annex C and the C-STORE,
  # C-FIND and C-MOVE statuses in PS3.4. Where a service gives a code its own
  # meaning, the name covers each meaning.
  @names %{
    0x0000 => "Success",
    0xFF00 => "Pending",
    0xFF01 => "Pending: Optional Keys not supported",
    0xFE00 => "Cancel",
    0x0001 => "Warning: Requested optional Attributes are not supported",
    0x0107 => "Warning: Attribute list error",
    0x0116 => "Warning: Attribute Value out of range",
    0xB000 => "Warning: Sub-operations complete, one or more failures or warnings",
    0xB006 => "Warning: Elements discarded",
    0xB007 => "Warning: Data Set does not match SOP Class",
    0x0110 => "Failure: Processing failure",
    0x0111 => "Failure: Duplicate SOP Instance",
    0x0112 => "Failure: No such SOP Instance",
    0x0117 => "Failure: Invalid SOP Instance",
    0x0119 => "Failure: Class-Instance conflict",
    0x0122 => "Refused: SOP Class not supported",
    0x0124 => "Refused: Not authorized",
    0x0210 => "Failure: Duplicate invocation",
    0x0211 => "Failure: Unrecognized operation",
    0x0212 => "Failure: Mistyped argument",
    0x0213 => "Failure: Resource limitation",
    0xA701 => "Refused: Out of Resources, Unable to calculate number of matches",
    0xA702 => "Refused: Out of Resources, Unable to perform sub-operations",
    0xA801 => "Refused: Move Destination unknown"
  }

  defmacro success, do: 0x0000

  @doc "Pending: matches or sub-operations are continuing."
  defmacro pending, do: 0xFF00

  @doc "Pending: matches are continuing, but one or more Optional Keys were not supported."
  defmacro pending_optional_keys_not_supported, do: 0xFF01

  defmacro cancel, do: 0xFE00

  @doc "Refused: SOP Class not supported."
  defmacro sop_class_not_supported, do: 0x0122

  @doc "Refused: Out of Resources."
  defmacro out_of_resources, do: 0xA700

  @doc "Error: Cannot understand."
  defmacro cannot_understand, do: 0xC000

  @doc "C-MOVE refused: Move Destination unknown (PS3.4 C.4.2.1.5)."
  defmacro move_destination_unknown, do: 0xA801

  @doc "Warning: sub-operations complete, one or more failures or warnings (PS3.4 C.4.2.1.5)."
  defmacro sub_operations_complete_with_failures, do: 0xB000

  @doc """
  The standard's name for a status `code`. A code within a range the standard
  defines (`0xA7xx`, `0xA9xx`, `0xCxxx`) is named by its range unless it has a
  meaning of its own.

      iex> Dcmix.Network.DIMSE.Status.describe(0xA801)
      "Refused: Move Destination unknown"

      iex> Dcmix.Network.DIMSE.Status.describe(0xC012)
      "Error: Cannot understand, or Unable to process"

      iex> Dcmix.Network.DIMSE.Status.describe(0x1234)
      "Unknown status"
  """
  @spec describe(non_neg_integer()) :: String.t()
  def describe(code) when is_map_key(@names, code), do: Map.fetch!(@names, code)
  def describe(code) when code in 0xA700..0xA7FF, do: "Refused: Out of Resources"

  def describe(code) when code in 0xA900..0xA9FF,
    do: "Error: Data Set or Identifier does not match SOP Class"

  def describe(code) when code in 0xC000..0xCFFF,
    do: "Error: Cannot understand, or Unable to process"

  def describe(_code), do: "Unknown status"
end
