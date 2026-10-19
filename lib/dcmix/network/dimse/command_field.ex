defmodule Dcmix.Network.DIMSE.CommandField do
  @moduledoc """
  DIMSE Command Field (0000,0100) values (PS3.7 E.1).

  These are macros so they can be used in patterns and guards as well as
  expressions; `require Dcmix.Network.DIMSE.CommandField` before use.
  """

  defmacro c_store_rq, do: 0x0001
  defmacro c_store_rsp, do: 0x8001
  defmacro c_get_rq, do: 0x0010
  defmacro c_get_rsp, do: 0x8010
  defmacro c_find_rq, do: 0x0020
  defmacro c_find_rsp, do: 0x8020
  defmacro c_move_rq, do: 0x0021
  defmacro c_move_rsp, do: 0x8021
  defmacro c_echo_rq, do: 0x0030
  defmacro c_echo_rsp, do: 0x8030
  defmacro c_cancel_rq, do: 0x0FFF
end
