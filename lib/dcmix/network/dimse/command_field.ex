defmodule Dcmix.Network.DIMSE.CommandField do
  @moduledoc """
  DIMSE Command Field (0000,0100) values (PS3.7 E.1).

  These are macros so they can be used in patterns and guards as well as
  expressions; `require Dcmix.Network.DIMSE.CommandField` before use.
  """

  defmacro c_echo_rq, do: 0x0030
  defmacro c_echo_rsp, do: 0x8030
end
