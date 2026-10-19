defmodule Mix.Tasks.Dcmix.Echoscu do
  @shortdoc "Verify a DICOM connection with C-ECHO, like dcmtk's echoscu"

  @moduledoc """
  Sends a C-ECHO to a DICOM node and reports whether it answered with
  success, like dcmtk's `echoscu`.

  ## Usage

      mix dcmix.echoscu [options] <peer> <port>

  ## Options

  dcmtk's short flags (`-aet`, `-aec`, `-to`, ...) work as well as these.

      --aetitle, -aet        Calling AE title (default: DCMIX)
      --call, -aec           Called AE title (default: ANY-SCP)
      --timeout, -to         Timeout in seconds (also --acse-timeout,
                             --dimse-timeout)
      --verbose, -v          Log the association and exchange

  ## Examples

      mix dcmix.echoscu localhost 4242
      mix dcmix.echoscu -aet DCMIX -aec ORTHANC localhost 4242
  """

  use Mix.Task

  alias Dcmix.Network
  alias Mix.Dcmix.NetworkCLI

  @impl Mix.Task
  def run(args) do
    with {:ok, opts, positional} <- NetworkCLI.parse(args),
         {:ok, addr} <- NetworkCLI.peer(positional) do
      echo(addr, NetworkCLI.connection_opts(opts))
    else
      {:error, message} -> NetworkCLI.fail!(message)
    end
  end

  defp echo(addr, opts) do
    case Network.echo(addr, opts) do
      :ok -> Mix.shell().info("C-ECHO to #{addr}: success")
      {:error, reason} -> NetworkCLI.fail!("C-ECHO to #{addr} failed: #{inspect(reason)}")
    end
  end
end
