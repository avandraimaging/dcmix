defmodule Dcmix.NetworkTest do
  use ExUnit.Case, async: true

  alias Dcmix.Network

  describe "find/1" do
    test "delegates to CFind.run and returns connection error" do
      assert {:error, {:connection_failed, _}} =
               Network.find(%{
                 addr: "127.0.0.1:1",
                 query: ["PatientName"],
                 calling_ae_title: "TEST",
                 called_ae_title: "MOCK"
               })
    end

    test "delegates to CFind.run and returns query parse error" do
      assert {:error, {:unknown_keyword, "BogusTag"}} =
               Network.find(%{
                 addr: "127.0.0.1:4242",
                 query: ["BogusTag"]
               })
    end
  end
end
