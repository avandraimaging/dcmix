defmodule Dcmix.Network.PDU.AssociateRJ do
  @moduledoc """
  Result, Source and Reason/Diag. values of an A-ASSOCIATE-RJ
  (PS3.8 Table 9-21).

  A reason only has meaning together with its source, so each reason is
  named with its source's prefix: `service_user_`, `acse_` or
  `presentation_`.

  These are macros so they can be used in patterns and guards as well as
  expressions; `require Dcmix.Network.PDU.AssociateRJ` before use.
  """

  # Result
  defmacro rejected_permanent, do: 1
  defmacro rejected_transient, do: 2

  # Source

  @doc "DICOM UL service-user."
  defmacro source_service_user, do: 1

  @doc "DICOM UL service-provider (ACSE related function)."
  defmacro source_acse, do: 2

  @doc "DICOM UL service-provider (Presentation related function)."
  defmacro source_presentation, do: 3

  # Reasons from the DICOM UL service-user
  defmacro service_user_no_reason_given, do: 1
  defmacro service_user_application_context_name_not_supported, do: 2
  defmacro service_user_calling_ae_title_not_recognized, do: 3
  defmacro service_user_called_ae_title_not_recognized, do: 7

  # Reasons from the DICOM UL service-provider (ACSE related function)
  defmacro acse_no_reason_given, do: 1
  defmacro acse_protocol_version_not_supported, do: 2

  # Reasons from the DICOM UL service-provider (Presentation related function)
  defmacro presentation_temporary_congestion, do: 1
  defmacro presentation_local_limit_exceeded, do: 2
end
