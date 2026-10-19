defmodule Mix.Tasks.Dcmix.Getscu do
  @shortdoc "Retrieve from a DICOM node with C-GET, like dcmtk's getscu"

  @moduledoc """
  Retrieves the instances matching the given keys with C-GET and writes them
  to the output directory, like dcmtk's `getscu`.

  ## Usage

      mix dcmix.getscu [options] <peer> <port>

  ## Options

  dcmtk's short flags (`-aet`, `-aec`, `-k`, `-od`, `-td`, ...) work as well
  as these.

      --key, -k              A key as Keyword=value or (gggg,eeee)=value; repeat
                             for each, including QueryRetrieveLevel
      --study, -S            Study Root model (the default)
      --patient, -P          Patient Root model
      --output-directory, -od  Where files are written (default: .)
      --aetitle, -aet        Calling AE title (default: DCMIX)
      --call, -aec           Called AE title (default: ANY-SCP)
      --timeout, -to         Timeout in seconds (also --acse-timeout,
                             --dimse-timeout)
      --max-pdu, -pdu        Max PDU length to propose
      --verbose, -v          Log the association and each response

  Exits with status 1 unless the final status is success.

  ## Examples

      mix dcmix.getscu -k QueryRetrieveLevel=STUDY -k StudyInstanceUID=1.2.3 \\
        -aec ORTHANC -od retrieved localhost 4242
  """

  use Mix.Task

  alias Dcmix.Network
  alias Mix.Dcmix.NetworkCLI

  @switches [key: :keep, study: :boolean, patient: :boolean, output_directory: :string]

  @impl Mix.Task
  def run(args) do
    with {:ok, opts, positional} <- NetworkCLI.parse(args, @switches),
         {:ok, addr} <- NetworkCLI.peer(positional),
         {:ok, identifier} <- NetworkCLI.identifier(Keyword.get_values(opts, :key)) do
      get_opts =
        NetworkCLI.connection_opts(opts) ++
          [
            query_model: NetworkCLI.query_model(opts),
            output_directory: Keyword.get(opts, :output_directory, ".")
          ]

      get(addr, identifier, get_opts)
    else
      {:error, message} -> NetworkCLI.fail!(message)
    end
  end

  defp get(addr, identifier, opts) do
    case Network.get(addr, identifier, opts) do
      {:ok, result} ->
        report(addr, result)
        if result.status != 0x0000, do: exit({:shutdown, 1})

      {:error, {:timeout, result}} ->
        report(addr, result)
        NetworkCLI.fail!("C-GET to #{addr} timed out")

      {:error, reason} ->
        NetworkCLI.fail!("C-GET to #{addr} failed: #{inspect(reason)}")
    end
  end

  defp report(addr, result) do
    Enum.each(result.files, &Mix.shell().info("Stored #{&1}"))

    Mix.shell().info(
      "C-GET from #{addr}: status #{NetworkCLI.status(result.status)}, " <>
        "#{result.completed} completed, #{result.failed} failed, #{result.warning} warning"
    )
  end
end
