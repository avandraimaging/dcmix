defmodule Dcmix.Network.ApplicationContext do
  @moduledoc """
  Application Context Names negotiated in association requests (PS3.7 A.2.1).
  """

  @dicom "1.2.840.10008.3.1.1.1"

  @doc "DICOM Application Context Name, the only one PS3.7 defines."
  def dicom, do: @dicom
end
