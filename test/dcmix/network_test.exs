defmodule Dcmix.NetworkTest do
  use ExUnit.Case, async: true

  alias Dcmix.{DataSet, Network}
  alias Dcmix.Network.Query

  describe "query/3" do
    test "delegates to CFind.query and returns connection error" do
      {:ok, query_ds} = Query.parse_terms(["PatientName"])

      assert {:error, {:connection_failed, _}} =
               Network.query("127.0.0.1:1", query_ds,
                 calling_ae_title: "TEST",
                 called_ae_title: "MOCK"
               )
    end

    test "accepts a caller-built DataSet without Query.parse_terms" do
      query_ds =
        DataSet.new()
        |> DataSet.put_element({0x0008, 0x0052}, :CS, "STUDY")
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Smith*")
        |> DataSet.put_element({0x0008, 0x0020}, :DA, "20250101-20251231")

      # Verifies the function accepts a raw DataSet (not just Query output)
      assert {:error, {:connection_failed, _}} =
               Network.query("127.0.0.1:1", query_ds)
    end
  end
end
