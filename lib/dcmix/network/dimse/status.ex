defmodule Dcmix.Network.DIMSE.Status do
  @moduledoc """
  DIMSE Status (0000,0900) codes (PS3.4, PS3.7 Annex C).

  These are macros so they can be used in patterns and guards as well as
  expressions; `require Dcmix.Network.DIMSE.Status` before use.
  """

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
end
