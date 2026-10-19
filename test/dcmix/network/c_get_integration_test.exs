defmodule Dcmix.Network.CGetIntegrationTest do
  @moduledoc """
  Retrieves from a real Orthanc. Excluded by default; run with
  `mix test --include integration`.

  Configure with `DCMIX_ORTHANC_HOST` (default `localhost`),
  `DCMIX_ORTHANC_PORT` (default `4242`), `DCMIX_ORTHANC_AE` (default
  `ORTHANC`) and `DCMIX_CALLING_AE` (default `DCMIX`). Orthanc must allow
  C-FIND and C-GET from the calling AE and hold at least one study.
  """

  use ExUnit.Case

  alias Dcmix.{DataSet, Parser}
  alias Dcmix.Network
  alias Dcmix.Network.CGet.Result

  @moduletag :integration

  setup do
    dir = Path.join(System.tmp_dir!(), "dcmix_cget_it_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    host = System.get_env("DCMIX_ORTHANC_HOST", "localhost")
    port = System.get_env("DCMIX_ORTHANC_PORT", "4242")

    opts = [
      calling_ae_title: System.get_env("DCMIX_CALLING_AE", "DCMIX"),
      called_ae_title: System.get_env("DCMIX_ORTHANC_AE", "ORTHANC"),
      timeout: 60_000
    ]

    {:ok, addr: "#{host}:#{port}", opts: opts, dir: dir}
  end

  test "retrieves the smallest study with study root C-GET", %{addr: addr, opts: opts, dir: dir} do
    find =
      DataSet.new()
      |> DataSet.put_element({0x0008, 0x0052}, :CS, "STUDY")
      |> DataSet.put_element({0x0020, 0x000D}, :UI, "")
      |> DataSet.put_element({0x0020, 0x1208}, :IS, "")

    assert {:ok, studies} = Network.query(addr, find, opts)
    with_instances = Enum.filter(studies, &((instance_count(&1) || 0) > 0))
    assert with_instances != [], "Orthanc has no study with instances"

    study = Enum.min_by(with_instances, &instance_count/1)

    study_uid = DataSet.get_string(study, {0x0020, 0x000D})

    identifier =
      DataSet.new()
      |> DataSet.put_element({0x0008, 0x0052}, :CS, "STUDY")
      |> DataSet.put_element({0x0020, 0x000D}, :UI, study_uid)

    assert {:ok, %Result{status: 0x0000, failed: 0} = result} =
             Network.get(
               addr,
               identifier,
               opts ++ [query_model: :study_root, output_directory: dir]
             )

    assert result.files != []
    assert length(result.files) == result.completed

    for path <- result.files do
      assert {:ok, ds} = Parser.parse_file(path)
      assert DataSet.get_string(ds, {0x0020, 0x000D}) == study_uid
    end
  end

  # Number of Study Related Instances, or nil when the SCP left it out or it
  # isn't a number
  defp instance_count(study) do
    case Integer.parse(to_string(DataSet.get_string(study, {0x0020, 0x1208}))) do
      {count, _rest} -> count
      :error -> nil
    end
  end
end
