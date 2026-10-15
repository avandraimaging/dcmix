defmodule Dcmix.Network.SOPClassUID do
  @moduledoc """
  SOP Class UIDs used as abstract syntaxes by the network services (PS3.4).
  """

  @verification "1.2.840.10008.1.1"

  @doc "Verification SOP Class, the abstract syntax of C-ECHO."
  def verification, do: @verification
end
