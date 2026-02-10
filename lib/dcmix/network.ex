defmodule Dcmix.Network do
  @moduledoc """
  DICOM networking operations.

  Provides Service Class User (SCU) functionality for DICOM network operations.
  Currently supports C-FIND for querying remote DICOM servers.

  ## Example

      {:ok, result} = Dcmix.Network.find(%{
        addr: "localhost:4242",
        query: ["PatientName", "StudyDate=20250101"],
        calling_ae_title: "MY_AE",
        called_ae_title: "PACS_AE"
      })

      # result.matches => 3
      # result.matched => [json_string, ...]
  """

  alias Dcmix.Network.CFind

  @doc """
  Performs a C-FIND query against a DICOM server.

  See `Dcmix.Network.CFind.run/1` for full documentation.
  """
  @spec find(map()) ::
          {:ok, %{matches: non_neg_integer(), matched: [String.t()]}} | {:error, term()}
  defdelegate find(opts), to: CFind, as: :run
end
