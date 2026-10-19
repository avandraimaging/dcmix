defmodule Mix.Tasks.Dcmix.Findscu do
  @shortdoc "Query a DICOM node with C-FIND, like dcmtk's findscu"

  @moduledoc """
  Queries a DICOM node with C-FIND and prints each match, like dcmtk's
  `findscu`. dcmix's C-FIND uses the Study Root model.

  ## Usage

      mix dcmix.findscu [options] <peer> <port>

  ## Options

  dcmtk's short flags (`-aet`, `-aec`, `-k`, `-to`, ...) work as well as
  these.

      --key, -k              A query key as Keyword=value or (gggg,eeee)=value;
                             an empty value asks for the key to be returned.
                             Repeat for each key, including QueryRetrieveLevel.
      --study, -S            Study Root model (the default and the only one)
      --aetitle, -aet        Calling AE title (default: DCMIX)
      --call, -aec           Called AE title (default: ANY-SCP)
      --timeout, -to         Timeout in seconds (also --acse-timeout,
                             --dimse-timeout)
      --max-pdu, -pdu        Max PDU length to propose
      --verbose, -v          Log the association and exchange

  ## Examples

      mix dcmix.findscu -S -k QueryRetrieveLevel=STUDY -k PatientID=12345 \\
        -k StudyInstanceUID= -k StudyDate= -aec ORTHANC localhost 4242
  """

  use Mix.Task

  alias Dcmix.Network
  alias Mix.Dcmix.NetworkCLI

  @impl Mix.Task
  def run(args) do
    with {:ok, opts, positional} <-
           NetworkCLI.parse(args, key: :keep, study: :boolean, patient: :boolean),
         :ok <- study_root_only(opts),
         {:ok, addr} <- NetworkCLI.peer(positional),
         {:ok, query} <- NetworkCLI.identifier(Keyword.get_values(opts, :key)) do
      find(addr, query, NetworkCLI.connection_opts(opts))
    else
      {:error, message} -> NetworkCLI.fail!(message)
    end
  end

  defp study_root_only(opts) do
    if opts[:patient],
      do: {:error, "dcmix's C-FIND supports the Study Root model only (-S)"},
      else: :ok
  end

  defp find(addr, query, opts) do
    case Network.query(addr, query, opts) do
      {:ok, matches} ->
        matches
        |> Enum.with_index(1)
        |> Enum.each(fn {match, n} -> Mix.shell().info("Match #{n}:\n#{Dcmix.dump(match)}") end)

        Mix.shell().info("C-FIND to #{addr}: #{length(matches)} matches")

      {:error, reason} ->
        NetworkCLI.fail!("C-FIND to #{addr} failed: #{inspect(reason)}")
    end
  end
end
