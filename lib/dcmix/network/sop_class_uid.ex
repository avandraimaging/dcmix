defmodule Dcmix.Network.SOPClassUID do
  @moduledoc """
  SOP Class UIDs used as abstract syntaxes by the network services (PS3.4).

  Storage SOP Classes proposed for C-GET sub-operations live in
  `Dcmix.Network.StorageSOPClasses`.
  """

  @verification "1.2.840.10008.1.1"
  @patient_root_query_retrieve_move "1.2.840.10008.5.1.4.1.2.1.2"
  @patient_root_query_retrieve_get "1.2.840.10008.5.1.4.1.2.1.3"
  @study_root_query_retrieve_find "1.2.840.10008.5.1.4.1.2.2.1"
  @study_root_query_retrieve_move "1.2.840.10008.5.1.4.1.2.2.2"
  @study_root_query_retrieve_get "1.2.840.10008.5.1.4.1.2.2.3"

  @doc "Verification SOP Class, the abstract syntax of C-ECHO."
  def verification, do: @verification

  @doc "Patient Root Query/Retrieve Information Model - MOVE."
  def patient_root_query_retrieve_move, do: @patient_root_query_retrieve_move

  @doc "Patient Root Query/Retrieve Information Model - GET."
  def patient_root_query_retrieve_get, do: @patient_root_query_retrieve_get

  @doc "Study Root Query/Retrieve Information Model - FIND."
  def study_root_query_retrieve_find, do: @study_root_query_retrieve_find

  @doc "Study Root Query/Retrieve Information Model - MOVE."
  def study_root_query_retrieve_move, do: @study_root_query_retrieve_move

  @doc "Study Root Query/Retrieve Information Model - GET."
  def study_root_query_retrieve_get, do: @study_root_query_retrieve_get
end
