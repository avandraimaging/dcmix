defmodule Mix.Tasks.Dcmix.NetworkSCUIntegrationTest do
  @moduledoc """
  Runs the dcmtk-style SCU tasks against a real Orthanc. Excluded by default;
  run with `mix test --include integration`.

  Uses the same settings as the C-MOVE integration test:
  `DCMIX_ORTHANC_HOST`, `DCMIX_ORTHANC_PORT`, `DCMIX_ORTHANC_AE`,
  `DCMIX_CALLING_AE` and `DCMIX_LISTENER_PORT`. Orthanc must hold at least
  one study and know the calling AE as a modality that reaches the listener.
  """

  use ExUnit.Case, async: false

  alias Dcmix.Network.Listener
  alias Mix.Tasks.Dcmix.{Echoscu, Findscu, Getscu, Movescu}

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
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    dir = Path.join(System.tmp_dir!(), "dcmix_scu_tasks_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    calling_ae = System.get_env("DCMIX_CALLING_AE", "DCMIX")

    peer = [
      "-aet",
      calling_ae,
      "-aec",
      System.get_env("DCMIX_ORTHANC_AE", "ORTHANC"),
      System.get_env("DCMIX_ORTHANC_HOST", "localhost"),
      System.get_env("DCMIX_ORTHANC_PORT", "4242")
    ]

    {:ok, peer: peer, dir: dir, calling_ae: calling_ae}
  end

  test "echoscu, findscu, getscu and movescu work against Orthanc", ctx do
    Echoscu.run(ctx.peer)
    assert_received {:mix_shell, :info, ["C-ECHO to " <> echo]}
    assert echo =~ "success"

    Findscu.run(
      [
        "-S",
        "-k",
        "QueryRetrieveLevel=STUDY",
        "-k",
        "StudyInstanceUID=",
        "-k",
        "NumberOfStudyRelatedInstances="
      ] ++
        ctx.peer
    )

    study_uid = smallest_study_uid(shell_info())

    study_keys = ["-k", "QueryRetrieveLevel=STUDY", "-k", "StudyInstanceUID=#{study_uid}"]

    Getscu.run(study_keys ++ ["-od", ctx.dir] ++ ctx.peer)
    assert [summary] = Enum.filter(shell_info(), &String.starts_with?(&1, "C-GET from"))
    assert summary =~ "status 0x0000"
    assert File.ls!(ctx.dir) != []

    listener_port = String.to_integer(System.get_env("DCMIX_LISTENER_PORT", "11112"))

    start_supervised!(
      {Listener,
       port: listener_port,
       ae_title: ctx.calling_ae,
       handler: {Handler, self()},
       storage_directory: Path.join(ctx.dir, "moved")}
    )

    Movescu.run(study_keys ++ ["-aem", ctx.calling_ae] ++ ctx.peer)
    assert [summary] = Enum.filter(shell_info(), &String.starts_with?(&1, "C-MOVE from"))
    assert summary =~ "status 0x0000"
    calling_ae = ctx.calling_ae
    assert_receive {:stored, %{move_originator_ae_title: ^calling_ae}}, 10_000
  end

  # All info lines printed so far
  defp shell_info(acc \\ []) do
    receive do
      {:mix_shell, :info, [line]} -> shell_info([line | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # From findscu's dumps, the study with the fewest instances (and at least one)
  defp smallest_study_uid(lines) do
    lines
    |> Enum.filter(&String.starts_with?(&1, "Match "))
    |> Enum.map(fn dump ->
      {uid(dump, "(0020,000D)"), count(dump)}
    end)
    |> Enum.filter(fn {_uid, count} -> count > 0 end)
    |> Enum.min_by(fn {_uid, count} -> count end)
    |> elem(0)
  end

  defp uid(dump, tag) do
    [_, value] = Regex.run(~r/#{Regex.escape(tag)} UI \S+ #\d+ \[([^\]]*)\]/, dump)
    value
  end

  defp count(dump) do
    case Regex.run(~r/\(0020,1208\) IS \S+ #\d+ \[\s*(\d+)/, dump) do
      [_, n] -> String.to_integer(n)
      nil -> 0
    end
  end
end
