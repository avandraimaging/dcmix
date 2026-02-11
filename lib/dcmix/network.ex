defmodule Dcmix.Network do
  @moduledoc """
  DICOM networking operations.

  Provides Service Class User (SCU) functionality for DICOM network operations.
  Currently supports C-FIND for querying remote DICOM servers.

  ## Example

      query =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "")
        |> Dcmix.DataSet.put_element({0x0008, 0x0020}, :DA, "20250101")

      {:ok, datasets} =
        Dcmix.Network.query("localhost:4242", query,
          calling_ae_title: "MY_AE",
          called_ae_title: "PACS_AE"
        )

      Enum.each(datasets, fn ds ->
        IO.puts(Dcmix.DataSet.get_string(ds, {0x0010, 0x0010}))
      end)
  """

  alias Dcmix.DataSet
  alias Dcmix.Network.CFind

  @doc """
  Performs a C-FIND query against a DICOM server.

  See `Dcmix.Network.CFind.query/3` for full documentation.
  """
  @spec query(String.t(), DataSet.t(), keyword()) ::
          {:ok, [DataSet.t()]} | {:error, term()}
  defdelegate query(addr, query_dataset, opts \\ []), to: CFind
end
