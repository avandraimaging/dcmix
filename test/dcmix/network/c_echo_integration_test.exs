defmodule Dcmix.Network.CEchoIntegrationTest do
  @moduledoc """
  Echoes a real Orthanc. Excluded by default; run with
  `mix test --include integration`.

  Configure with `DCMIX_ORTHANC_HOST` (default `localhost`),
  `DCMIX_ORTHANC_PORT` (default `4242`), `DCMIX_ORTHANC_AE` (default
  `ORTHANC`) and `DCMIX_CALLING_AE` (default `DCMIX`).
  """

  use ExUnit.Case

  alias Dcmix.Network

  @moduletag :integration

  test "a real Orthanc answers a C-ECHO with success" do
    host = System.get_env("DCMIX_ORTHANC_HOST", "localhost")
    port = System.get_env("DCMIX_ORTHANC_PORT", "4242")

    assert :ok =
             Network.echo("#{host}:#{port}",
               calling_ae_title: System.get_env("DCMIX_CALLING_AE", "DCMIX"),
               called_ae_title: System.get_env("DCMIX_ORTHANC_AE", "ORTHANC")
             )
  end
end
