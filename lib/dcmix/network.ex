defmodule Dcmix.Network do
  @moduledoc """
  DICOM networking operations.

  Provides Service Class User (SCU) functionality for DICOM network operations.
  Currently supports C-ECHO for verifying a connection, C-FIND for querying
  remote DICOM servers, C-GET for retrieving instances from them, and C-MOVE
  for having them send instances to a Storage SCP.

  To accept associations as an SCP, answering C-ECHO and storing instances
  sent with C-STORE, see `Dcmix.Network.Listener`.

  ## C-ECHO example

      :ok = Dcmix.Network.echo("localhost:4242", called_ae_title: "PACS_AE")

  ## C-FIND example

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

  ## C-GET example

      identifier =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0008, 0x0052}, :CS, "STUDY")
        |> Dcmix.DataSet.put_element({0x0020, 0x000D}, :UI, "1.2.3.4")

      {:ok, %Dcmix.Network.CGet.Result{files: files}} =
        Dcmix.Network.get("localhost:4242", identifier,
          called_ae_title: "PACS_AE",
          query_model: :study_root,
          output_directory: "retrieved"
        )

  ## C-MOVE example

      identifier =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0008, 0x0052}, :CS, "STUDY")
        |> Dcmix.DataSet.put_element({0x0020, 0x000D}, :UI, "1.2.3.4")

      {:ok, %Dcmix.Network.CMove.Result{completed: completed}} =
        Dcmix.Network.move("localhost:4242", identifier,
          called_ae_title: "PACS_AE",
          destination_ae_title: "MY_SCP",
          query_model: :study_root
        )
  """

  alias Dcmix.DataSet
  alias Dcmix.Network.{CEcho, CFind, CGet, CMove}

  @doc """
  Sends a C-ECHO to a DICOM node, verifying it accepts an association and
  answers with success.

  See `Dcmix.Network.CEcho.echo/2` for full documentation.
  """
  @spec echo(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate echo(addr, opts \\ []), to: CEcho

  @doc """
  Performs a C-FIND query against a DICOM server.

  See `Dcmix.Network.CFind.query/3` for full documentation.
  """
  @spec query(String.t(), DataSet.t(), keyword()) ::
          {:ok, [DataSet.t()]} | {:error, term()}
  defdelegate query(addr, query_dataset, opts \\ []), to: CFind

  @doc """
  Performs a C-GET retrieve against a DICOM server, storing the instances it
  sends back.

  See `Dcmix.Network.CGet.get/3` for full documentation.
  """
  @spec get(String.t(), DataSet.t(), keyword()) ::
          {:ok, CGet.Result.t()} | {:error, term()}
  defdelegate get(addr, query_dataset, opts \\ []), to: CGet

  @doc """
  Performs a C-MOVE against a DICOM server, which sends the matching
  instances to the Storage SCP titled `:destination_ae_title`.

  See `Dcmix.Network.CMove.move/3` for full documentation.
  """
  @spec move(String.t(), DataSet.t(), keyword()) ::
          {:ok, CMove.Result.t()} | {:error, term()}
  defdelegate move(addr, identifier, opts \\ []), to: CMove
end
