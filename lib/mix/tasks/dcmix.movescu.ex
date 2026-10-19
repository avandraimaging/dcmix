defmodule Mix.Tasks.Dcmix.Movescu do
  @shortdoc "Move from a DICOM node to a Storage SCP with C-MOVE, like dcmtk's movescu"

  @moduledoc """
  Asks a DICOM node to send the instances matching the given keys to a
  Storage SCP with C-MOVE, printing each response, like dcmtk's `movescu`.
  The instances go to the move destination over a separate association, so
  run a Storage SCP there (e.g. dcmtk's `storescp`, or a dcmix listener).

  ## Usage

      mix dcmix.movescu [options] <peer> <port>

  ## Options

  dcmtk's short flags (`-aet`, `-aec`, `-aem`, `-k`, `-td`, ...) work as well
  as these.

      --key, -k              A key as Keyword=value or (gggg,eeee)=value; repeat
                             for each, including QueryRetrieveLevel
      --move, -aem           Move destination AE title (default: the calling
                             AE title, as in dcmtk)
      --study, -S            Study Root model (the default)
      --patient, -P          Patient Root model
      --aetitle, -aet        Calling AE title (default: DCMIX)
      --call, -aec           Called AE title (default: ANY-SCP)
      --timeout, -to         Timeout in seconds (also --acse-timeout,
                             --dimse-timeout)
      --max-pdu, -pdu        Max PDU length to propose
      --verbose, -v          Log the association

  Exits with status 1 unless the final status is success.

  ## Examples

      mix dcmix.movescu -k QueryRetrieveLevel=IMAGE -k StudyInstanceUID=1.2.3 \\
        -k SeriesInstanceUID=1.2.3.4 -k SOPInstanceUID=1.2.3.4.5 \\
        -aet DCMIX -aec ORTHANC -aem DCMIX localhost 4242
  """

  use Mix.Task

  alias Dcmix.Network
  alias Mix.Dcmix.NetworkCLI

  @switches [key: :keep, move: :string, study: :boolean, patient: :boolean]

  @impl Mix.Task
  def run(args) do
    with {:ok, opts, positional} <- NetworkCLI.parse(args, @switches),
         {:ok, addr} <- NetworkCLI.peer(positional),
         {:ok, identifier} <- NetworkCLI.identifier(Keyword.get_values(opts, :key)) do
      move_opts =
        NetworkCLI.connection_opts(opts) ++
          [
            destination_ae_title: opts[:move] || opts[:aetitle] || "DCMIX",
            query_model: NetworkCLI.query_model(opts),
            on_response: &print_response/1
          ]

      move(addr, identifier, move_opts)
    else
      {:error, message} -> NetworkCLI.fail!(message)
    end
  end

  defp move(addr, identifier, opts) do
    case Network.move(addr, identifier, opts) do
      {:ok, result} ->
        report(addr, opts[:destination_ae_title], result)
        if result.status != 0x0000, do: exit({:shutdown, 1})

      {:error, {:timeout, result}} ->
        report(addr, opts[:destination_ae_title], result)
        NetworkCLI.fail!("C-MOVE to #{addr} timed out")

      {:error, reason} ->
        NetworkCLI.fail!("C-MOVE to #{addr} failed: #{inspect(reason)}")
    end
  end

  defp print_response(%{final: false} = response) do
    Mix.shell().info(
      "Pending: #{response.remaining || "?"} remaining, #{response.completed || 0} completed, " <>
        "#{response.failed || 0} failed, #{response.warning || 0} warning"
    )

    :cont
  end

  defp print_response(_final), do: :cont

  defp report(addr, destination, result) do
    Enum.each(result.failed_sop_instance_uids, &Mix.shell().info("Failed: #{&1}"))

    Mix.shell().info(
      "C-MOVE from #{addr} to #{destination}: status #{NetworkCLI.status(result.status)}, " <>
        "#{result.completed} completed, #{result.failed} failed, #{result.warning} warning"
    )
  end
end
