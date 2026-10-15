defmodule Dcmix.Network.PDU.Type do
  @moduledoc """
  Upper Layer PDU type codes (PS3.8 9.3).

  These are macros so they can be used in patterns and guards as well as
  expressions; `require Dcmix.Network.PDU.Type` before use.
  """

  defmacro associate_rq, do: 0x01
  defmacro associate_ac, do: 0x02
  defmacro associate_rj, do: 0x03
  defmacro p_data_tf, do: 0x04
  defmacro release_rq, do: 0x05
  defmacro release_rp, do: 0x06
  defmacro abort, do: 0x07
end
