if Code.ensure_loaded?(ThousandIsland) do
  defmodule Dcmix.Network.Listener do
    @moduledoc """
    Listens for DICOM associations on a TCP port, as an SCP.

    Each accepted connection is served in its own process by
    `Dcmix.Network.SCP`, which answers C-ECHO and, given a handler, stores
    instances sent with C-STORE (see `Dcmix.Network.SCP.Handler`). The
    listener is a child spec for your own supervision tree; dcmix starts
    nothing on its own.

        children = [
          {Dcmix.Network.Listener,
           port: 11112,
           ae_title: "MY_SCP",
           handler: {MyApp.StoreHandler, []},
           storage_directory: "/var/lib/my_app/incoming"}
        ]

        Supervisor.start_link(children, strategy: :one_for_one)

    Requires the optional `:thousand_island` dependency, which accepts and
    supervises the connections. Add it to your own deps:

        {:thousand_island, "~> 1.5"}

    ## Options
    - `:port` - TCP port to listen on; 0 picks a free one, which `port/1`
      returns (required)
    - `:ae_title` - our AE title; a requestor calling any other is rejected
      (required)
    - `:max_associations` - how many associations are served at once; one
      more is rejected as rejected-transient, local-limit-exceeded
      (default: 10)
    - `:max_pdu_length` - the largest PDU we accept (default: 16384)
    - `:timeout` - how long to wait for a requestor's next PDU, in ms,
      before aborting (default: 60000)
    - `:handler` - a module implementing `Dcmix.Network.SCP.Handler`, or
      `{module, arg}`; with it, the Storage SOP Classes are accepted as well
      as Verification
    - `:storage_directory` - where instances are written, created if missing
      (required with `:handler`)
    - `:storage_sop_classes` - Storage SOP Classes accepted (default:
      `Dcmix.Network.StorageSOPClasses.uids/0`)
    - `:storage_transfer_syntaxes` - transfer syntaxes accepted for them,
      compressed ones included, taken as sent (default: every transfer
      syntax in `Dcmix.Parser.TransferSyntax.all/0`)

    `start_link/1` returns `{:error, {:storage_directory, reason}}` when the
    storage directory can't be created.
    """

    alias Dcmix.Network.Listener.Connection

    @default_max_associations 10

    @doc """
    Returns a child spec for the listener.
    """
    @spec child_spec(keyword()) :: Supervisor.child_spec()
    def child_spec(opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
    end

    @doc """
    Starts the listener, linked to the calling process.
    """
    @spec start_link(keyword()) :: Supervisor.on_start()
    def start_link(opts) do
      opts =
        Keyword.validate!(opts, [
          :port,
          :ae_title,
          :max_pdu_length,
          :timeout,
          :handler,
          :storage_directory,
          :storage_sop_classes,
          :storage_transfer_syntaxes,
          max_associations: @default_max_associations
        ])

      with :ok <- prepare_storage(opts) do
        ThousandIsland.start_link(
          port: Keyword.fetch!(opts, :port),
          handler_module: Connection,
          handler_options: handler_options(opts)
        )
      end
    end

    @doc """
    Returns the TCP port the listener is bound to.
    """
    @spec port(Supervisor.supervisor()) :: {:ok, :inet.port_number()} | {:error, term()}
    def port(listener) do
      with {:ok, {_address, port}} <- ThousandIsland.listener_info(listener) do
        {:ok, port}
      end
    end

    defp prepare_storage(opts) do
      case Keyword.fetch(opts, :handler) do
        {:ok, _handler} -> create_storage_directory(Keyword.fetch!(opts, :storage_directory))
        :error -> :ok
      end
    end

    defp create_storage_directory(directory) do
      case File.mkdir_p(directory) do
        :ok -> :ok
        {:error, reason} -> {:error, {:storage_directory, reason}}
      end
    end

    defp handler_options(opts) do
      scp_opts =
        [ae_title: Keyword.fetch!(opts, :ae_title)] ++
          Keyword.take(opts, [
            :max_pdu_length,
            :timeout,
            :storage_directory,
            :storage_sop_classes,
            :storage_transfer_syntaxes
          ]) ++ scp_handler(opts)

      %{
        scp_opts: scp_opts,
        max_associations: Keyword.fetch!(opts, :max_associations),
        associations: :counters.new(1, [:atomics])
      }
    end

    defp scp_handler(opts) do
      case Keyword.fetch(opts, :handler) do
        {:ok, {module, arg}} -> [handler: {module, arg}]
        {:ok, module} when is_atom(module) -> [handler: {module, nil}]
        :error -> []
      end
    end
  end

  defmodule Dcmix.Network.Listener.Connection do
    @moduledoc false

    # One process per connection. The association is served synchronously
    # within handle_connection/2, while the socket is still passive.

    use ThousandIsland.Handler

    alias Dcmix.Network.{Negotiation, SCP}

    @impl ThousandIsland.Handler
    def handle_connection(%ThousandIsland.Socket{socket: socket}, config) do
      :counters.add(config.associations, 1, 1)

      try do
        if :counters.get(config.associations, 1) > config.max_associations,
          do: SCP.refuse(socket, Negotiation.local_limit_exceeded(), config.scp_opts),
          else: SCP.serve(socket, config.scp_opts)
      after
        :counters.sub(config.associations, 1, 1)
      end

      {:close, config}
    end
  end
else
  defmodule Dcmix.Network.Listener do
    @moduledoc """
    Listens for DICOM associations on a TCP port, as an SCP.

    This needs the optional `:thousand_island` dependency. Add it to your
    deps to use the listener:

        {:thousand_island, "~> 1.5"}
    """

    @message "Dcmix.Network.Listener needs the :thousand_island dependency; " <>
               "add {:thousand_island, \"~> 1.5\"} to your deps"

    @doc false
    def child_spec(_opts), do: raise(@message)

    @doc false
    def start_link(_opts), do: raise(@message)

    @doc false
    def port(_listener), do: raise(@message)
  end
end
