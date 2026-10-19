defmodule Mix.Tasks.Dcmix.Storescp do
  @shortdoc "Receive instances with a Storage SCP, like dcmtk's storescp"

  @moduledoc """
  Runs a dcmix listener as a Storage SCP until stopped, like dcmtk's
  `storescp`. It answers C-ECHO and writes each instance sent with C-STORE
  to the output directory, logging each one.

  Needs the optional `:thousand_island` dependency, as
  `Dcmix.Network.Listener` does.

  ## Usage

      mix dcmix.storescp [options] <port>

  ## Options

  dcmtk's short flags (`-aet`, `-od`, `-ta`, `-td`, `-pdu`) work as well as
  these.

      --aetitle, -aet          Our AE title; a requestor calling any other is
                               rejected (default: DCMIX)
      --output-directory, -od  Where instances are written (default: .)
      --max-associations       Associations served at once (default: 10)
      --timeout, -to           Seconds to wait for a requestor's next PDU
                               (also --acse-timeout, --dimse-timeout)
      --max-pdu, -pdu          Largest PDU we accept

  Port 0 picks a free port, which is printed.

  ## Examples

      mix dcmix.storescp -aet DCMIX -od incoming 11112
  """

  use Mix.Task

  alias Dcmix.Network.Listener
  alias Mix.Dcmix.NetworkCLI

  @switches [output_directory: :string, max_associations: :integer]

  @impl Mix.Task
  def run(args) do
    case start(args) do
      {:ok, _listener} -> Process.sleep(:infinity)
      {:error, message} -> NetworkCLI.fail!(message)
    end
  end

  @doc """
  Starts the listener as `run/1` does, without blocking, returning
  `{:ok, listener}` or `{:error, message}`.
  """
  @spec start([String.t()]) :: {:ok, pid()} | {:error, String.t()}
  def start(args) do
    with {:ok, opts, positional} <- NetworkCLI.parse(args, @switches),
         {:ok, port} <- port(positional),
         :ok <- start_thousand_island() do
      listen(port, opts)
    end
  end

  defp port([port | _]) do
    case Integer.parse(port) do
      {port, ""} when port in 0..65_535 -> {:ok, port}
      _ -> {:error, "invalid port #{inspect(port)}"}
    end
  end

  defp port([]), do: {:error, "expected the port to listen on, e.g. 11112"}

  # Only ThousandIsland is started, not the calling project's application
  defp start_thousand_island do
    Mix.Task.run("app.config")

    if Code.ensure_loaded?(ThousandIsland) do
      {:ok, _apps} = Application.ensure_all_started(:thousand_island)
      :ok
    else
      {:error,
       "mix dcmix.storescp needs the :thousand_island dependency; " <>
         "add {:thousand_island, \"~> 1.6\"} to your deps"}
    end
  end

  defp listen(port, opts) do
    ae_title = Keyword.get(opts, :aetitle, "DCMIX")
    directory = Keyword.get(opts, :output_directory, ".")
    connection = NetworkCLI.connection_opts(opts)

    listener_opts =
      [
        port: port,
        ae_title: ae_title,
        handler: __MODULE__.LogHandler,
        storage_directory: directory,
        timeout: connection[:timeout],
        max_pdu_length: connection[:max_pdu_length],
        max_associations: opts[:max_associations]
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case Listener.start_link(listener_opts) do
      {:ok, listener} ->
        {:ok, bound_port} = Listener.port(listener)

        Mix.shell().info(
          "Storage SCP #{ae_title} listening on port #{bound_port}, storing to #{directory}"
        )

        {:ok, listener}

      {:error, reason} ->
        {:error, "couldn't start the listener: #{inspect(reason)}"}
    end
  end

  defmodule LogHandler do
    @moduledoc false

    # Leaves each instance in the output directory and logs it

    @behaviour Dcmix.Network.SCP.Handler

    require Logger

    @impl true
    def handle_store(instance, state) do
      Logger.info(
        "Stored #{instance.path} (SOP Class #{instance.sop_class_uid}, " <>
          "transfer syntax #{instance.transfer_syntax}) from #{instance.calling_ae_title}" <>
          move_originator(instance)
      )

      {:reply, 0x0000, state}
    end

    defp move_originator(%{move_originator_ae_title: nil}), do: ""

    defp move_originator(instance),
      do:
        ", moved for #{instance.move_originator_ae_title} (message #{instance.move_originator_message_id})"
  end
end
