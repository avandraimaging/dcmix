defmodule Dcmix.Network.PDU.PresentationContextResult do
  @moduledoc """
  Result/Reason values of a presentation context in an A-ASSOCIATE-AC
  (PS3.8 Table 9-18).

  These are macros so they can be used in patterns and guards as well as
  expressions; `require Dcmix.Network.PDU.PresentationContextResult` before use.
  """

  defmacro acceptance, do: 0

  @doc "User rejection."
  defmacro user_rejection, do: 1

  @doc "No reason (provider rejection)."
  defmacro no_reason, do: 2

  defmacro abstract_syntax_not_supported, do: 3
  defmacro transfer_syntaxes_not_supported, do: 4
end
