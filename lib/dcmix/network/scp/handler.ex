defmodule Dcmix.Network.SCP.Handler do
  @moduledoc """
  A Storage SCP's handler: what happens to each instance a listener receives.

  Give a listener a handler, and a directory to store into, and it accepts
  the Storage SOP Classes as well as Verification:

      {Dcmix.Network.Listener,
       port: 11112,
       ae_title: "MY_SCP",
       handler: {MyApp.StoreHandler, []},
       storage_directory: "/var/lib/my_app/incoming"}

  dcmix writes each instance to a Part 10 file in the storage directory as it
  arrives (see `Dcmix.Network.InstanceFile`), then calls `c:handle_store/2`
  with the file's path and the instance's UIDs. The file is the handler's
  from then on: move it, queue it for processing or delete it. The status the
  handler returns is sent to the requestor in the C-STORE-RSP.

  When dcmix can't store an instance (the disk is full, or its SOP Instance
  UID can't name a file), it answers Out of Resources or Cannot Understand
  itself, deletes what it wrote, and doesn't call the handler.

  Each association has its own handler state, from `c:init/2`. The handler
  runs in the association's process, so a slow handler slows only that
  requestor, which waits for each C-STORE-RSP.

  If the handler raises, the association's process exits and the connection
  closes without a C-STORE-RSP, so the requestor counts the instance as
  failed. dcmix doesn't recover it.

  An instance being received when the listener stops is dropped and the
  requestor counts it as failed; the handler isn't called for it. Its
  `<name>.part` file is deleted when the association ends, but can be left in
  the storage directory if the association's process is killed, e.g. by the
  listener's shutdown timeout. Leftover `.part` files are safe to delete.

  ## Example

      defmodule MyApp.StoreHandler do
        @behaviour Dcmix.Network.SCP.Handler

        require Dcmix.Network.DIMSE.Status, as: Status

        @impl true
        def init(association, _arg), do: {:ok, %{calling_ae_title: association.calling_ae_title}}

        @impl true
        def handle_store(instance, state) do
          :ok = MyApp.Incoming.enqueue(instance.path, state.calling_ae_title)
          {:reply, Status.success(), state}
        end
      end
  """

  @typedoc """
  The association a handler serves: the AE titles from its A-ASSOCIATE-RQ and
  the requestor's address.
  """
  @type association :: %{
          calling_ae_title: String.t(),
          called_ae_title: String.t(),
          peer: {:inet.ip_address(), :inet.port_number()} | nil
        }

  @typedoc """
  An instance stored to `path`.

  The SOP Class and Instance UIDs come from the C-STORE-RQ. The Study and
  Series Instance UIDs are read back from the stored file's header, so a
  handler can match the instance to whatever was asked for, at any level, by
  its UIDs; they are `nil` when the header can't be read or lacks them.

  The Move Originator fields are set when the instance was sent as a
  sub-operation of a C-MOVE, naming the AE that asked for the move and the
  message ID of its C-MOVE-RQ. Older SCPs don't always set them, so the UIDs
  are the dependable way to match an instance to its move.
  """
  @type instance :: %{
          path: Path.t(),
          sop_class_uid: String.t(),
          sop_instance_uid: String.t(),
          study_instance_uid: String.t() | nil,
          series_instance_uid: String.t() | nil,
          transfer_syntax: String.t(),
          calling_ae_title: String.t(),
          move_originator_ae_title: String.t() | nil,
          move_originator_message_id: non_neg_integer() | nil
        }

  @doc """
  Starts the handler's state for an association, once it is accepted.
  Optional; without it the state is the handler's argument.
  """
  @callback init(association(), arg :: term()) :: {:ok, state :: term()}

  @doc """
  Handles an instance stored to `instance.path`, returning the C-STORE-RSP
  status, e.g. `Dcmix.Network.DIMSE.Status.success()`.
  """
  @callback handle_store(instance(), state :: term()) ::
              {:reply, status :: non_neg_integer(), state :: term()}

  @optional_callbacks init: 2
end
