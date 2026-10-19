defmodule Dcmix.Network.CMoveIntegrationTest do
  @moduledoc """
  Moves from a real Orthanc to a dcmix listener. Excluded by default; run with
  `mix test --include integration`.

  Configure with `DCMIX_ORTHANC_HOST` (default `localhost`),
  `DCMIX_ORTHANC_PORT` (default `4242`), `DCMIX_ORTHANC_AE` (default
  `ORTHANC`), `DCMIX_CALLING_AE` (default `DCMIX`), and the listener's
  `DCMIX_LISTENER_PORT` (default `11112`). Orthanc must hold at least one
  study and know the calling AE as a modality whose address reaches the
  listener (e.g. `["DCMIX", "host.docker.internal", 11112]` when Orthanc
  runs in Docker), since that AE is also the move destination.
  """

  use ExUnit.Case

  alias Dcmix.DataSet
  alias Dcmix.Network
  alias Dcmix.Network.{CMove, Listener}

  require Dcmix.Network.DIMSE.Status, as: Status

  @moduletag :integration

  defmodule Handler do
    @moduledoc false
    @behaviour Dcmix.Network.SCP.Handler

    @impl true
    def handle_store(instance, test) do
      send(test, {:stored, instance})
      {:reply, 0x0000, test}
    end
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "dcmix_cmove_it_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    host = System.get_env("DCMIX_ORTHANC_HOST", "localhost")
    port = System.get_env("DCMIX_ORTHANC_PORT", "4242")
    calling_ae = System.get_env("DCMIX_CALLING_AE", "DCMIX")
    listener_port = String.to_integer(System.get_env("DCMIX_LISTENER_PORT", "11112"))

    start_supervised!(
      {Listener,
       port: listener_port,
       ae_title: calling_ae,
       handler: {Handler, self()},
       storage_directory: dir}
    )

    opts = [
      calling_ae_title: calling_ae,
      called_ae_title: System.get_env("DCMIX_ORTHANC_AE", "ORTHANC"),
      destination_ae_title: calling_ae,
      query_model: :study_root,
      timeout: 60_000
    ]

    {:ok, addr: "#{host}:#{port}", opts: opts}
  end

  test "moves the smallest study, then one of its instances, to our listener",
       %{addr: addr, opts: opts} do
    study_uid = smallest_study(addr, opts)
    test = self()

    on_response = fn response ->
      send(test, {:response, response})
      :cont
    end

    study = identifier("STUDY", study_uid: study_uid)

    assert {:ok, %CMove.Result{status: Status.success(), failed: 0} = result} =
             Network.move(addr, study, opts ++ [message_id: 4321, on_response: on_response])

    assert result.completed > 0
    assert_received {:response, %CMove.Response{final: true}}

    instances = receive_stored(result.completed)

    for instance <- instances do
      assert instance.move_originator_ae_title == opts[:calling_ae_title]
      assert instance.move_originator_message_id == 4321
      assert {:ok, ds} = Dcmix.read_file(instance.path, stop_before_pixels: true)
      assert DataSet.get_string(ds, {0x0020, 0x000D}) == study_uid
    end

    # One instance by its UIDs, as an instance-level retrieve does
    [first | _] = instances
    {:ok, header} = Dcmix.read_file(first.path, stop_before_pixels: true)

    image =
      identifier("IMAGE",
        study_uid: study_uid,
        series_uid: DataSet.get_string(header, {0x0020, 0x000E}),
        sop_instance_uid: first.sop_instance_uid
      )

    assert {:ok, %CMove.Result{status: Status.success(), completed: 1}} =
             Network.move(addr, image, opts ++ [message_id: 4322])

    assert [%{sop_instance_uid: uid, move_originator_message_id: 4322}] = receive_stored(1)
    assert uid == first.sop_instance_uid
  end

  defp smallest_study(addr, opts) do
    find =
      DataSet.new()
      |> DataSet.put_element({0x0008, 0x0052}, :CS, "STUDY")
      |> DataSet.put_element({0x0020, 0x000D}, :UI, "")
      |> DataSet.put_element({0x0020, 0x1208}, :IS, "")

    assert {:ok, [_ | _] = studies} = Network.query(addr, find, opts)

    studies
    |> Enum.min_by(fn ds ->
      ds |> DataSet.get_string({0x0020, 0x1208}) |> to_string() |> Integer.parse() |> elem(0)
    end)
    |> DataSet.get_string({0x0020, 0x000D})
  end

  @uid_tags [
    study_uid: {0x0020, 0x000D},
    series_uid: {0x0020, 0x000E},
    sop_instance_uid: {0x0008, 0x0018}
  ]

  defp identifier(level, uids) do
    base = DataSet.put_element(DataSet.new(), {0x0008, 0x0052}, :CS, level)

    Enum.reduce(uids, base, fn {key, uid}, ds ->
      DataSet.put_element(ds, Keyword.fetch!(@uid_tags, key), :UI, uid)
    end)
  end

  defp receive_stored(count) do
    for _ <- 1..count do
      assert_receive {:stored, instance}, 10_000
      instance
    end
  end
end
