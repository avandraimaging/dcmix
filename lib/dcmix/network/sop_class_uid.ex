defmodule Dcmix.Network.SOPClassUID do
  @moduledoc """
  SOP Class UIDs used as abstract syntaxes by the network services (PS3.4).

  Each Storage SOP Class in `Dcmix.Network.StorageSOPClasses` has a function
  named for its PS3.6 keyword in snake case:
  `key_object_selection_document_storage/0` is
  KeyObjectSelectionDocumentStorage, `comprehensive_3d_sr_storage/0`
  Comprehensive3DSRStorage. The lists proposed for C-GET and accepted by a
  Storage SCP are there.
  """

  alias Dcmix.Network.StorageSOPClasses

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

  # A keyword's words, its digits kept with a following D (3D), in snake case.
  # Keywords run some abbreviations together, which are split here.
  run_together = %{"CADSR" => ["CAD", "SR"], "XAXRF" => ["XA", "XRF"], "VOILUT" => ["VOI", "LUT"]}

  function_name = fn keyword ->
    ~r/\d+D(?=[A-Z]|$)|\d+|[A-Z]+(?=[A-Z][a-z]|\d|$)|[A-Z]?[a-z]+|[A-Z]+/
    |> Regex.scan(keyword)
    |> Enum.flat_map(fn [word] -> Map.get(run_together, word, [word]) end)
    |> Enum.map_join("_", &String.downcase/1)
    |> String.to_atom()
  end

  for {keyword, uid} <- StorageSOPClasses.classes() do
    @doc "#{keyword}, `#{uid}`."
    @spec unquote(function_name.(keyword))() :: String.t()
    def unquote(function_name.(keyword))(), do: unquote(uid)
  end
end
