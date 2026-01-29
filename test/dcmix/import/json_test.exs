defmodule Dcmix.Import.JSONTest do
  use ExUnit.Case, async: true

  alias Dcmix.Import.JSON
  alias Dcmix.DataSet

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "nema_mr_brain_512x512.dcm")

  describe "decode/2" do
    test "decodes simple DICOM JSON" do
      json = """
      {
        "00100010": {"vr": "PN", "Value": [{"Alphabetic": "Doe^John"}]},
        "00100020": {"vr": "LO", "Value": ["12345"]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "Doe^John"
      assert DataSet.get_string(dataset, {0x0010, 0x0020}) == "12345"
    end

    test "decodes numeric values" do
      json = """
      {
        "00280010": {"vr": "US", "Value": [512]},
        "00280011": {"vr": "US", "Value": [512]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_value(dataset, {0x0028, 0x0010}) == 512
      assert DataSet.get_value(dataset, {0x0028, 0x0011}) == 512
    end

    test "decodes multiple values" do
      json = """
      {
        "00080008": {"vr": "CS", "Value": ["ORIGINAL", "PRIMARY"]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_string(dataset, {0x0008, 0x0008}) == "ORIGINAL\\PRIMARY"
    end

    test "decodes InlineBinary" do
      base64_data = Base.encode64(<<1, 2, 3, 4>>)

      json = """
      {
        "7FE00010": {"vr": "OW", "InlineBinary": "#{base64_data}"}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_value(dataset, {0x7FE0, 0x0010}) == <<1, 2, 3, 4>>
    end

    test "decodes sequences" do
      json = """
      {
        "00081115": {
          "vr": "SQ",
          "Value": [
            {"00081150": {"vr": "UI", "Value": ["1.2.3"]}},
            {"00081150": {"vr": "UI", "Value": ["4.5.6"]}}
          ]
        }
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      element = DataSet.get(dataset, {0x0008, 0x1115})
      assert element.vr == :SQ
      assert length(element.value) == 2
    end

    test "decodes DS and IS values as strings" do
      json = """
      {
        "00181050": {"vr": "DS", "Value": [1.5, 2.0]},
        "00200013": {"vr": "IS", "Value": [1]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      # DS values are stored as strings
      assert DataSet.get_string(dataset, {0x0018, 0x1050}) == "1.5\\2.0"
      assert DataSet.get_string(dataset, {0x0020, 0x0013}) == "1"
    end

    test "decodes empty values" do
      json = """
      {
        "00100010": {"vr": "PN"}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_value(dataset, {0x0010, 0x0010}) == nil
    end

    test "merges with template dataset" do
      template =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Template^Name")
        |> DataSet.put_element({0x0010, 0x0030}, :DA, "19800101")

      json = """
      {
        "00100010": {"vr": "PN", "Value": [{"Alphabetic": "New^Name"}]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json, template: template)
      # Name should be overwritten
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "New^Name"
      # Birth date should be preserved from template
      assert DataSet.get_string(dataset, {0x0010, 0x0030}) == "19800101"
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_decode_error, _}} = JSON.decode("not json")
    end

    test "handles AT values" do
      json = """
      {
        "00209165": {"vr": "AT", "Value": ["00100010"]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_value(dataset, {0x0020, 0x9165}) == {0x0010, 0x0010}
    end
  end

  describe "decode_file/2" do
    test "decodes JSON file" do
      tmp_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(100_000)}.json")

      json = """
      {
        "00100010": {"vr": "PN", "Value": [{"Alphabetic": "Test^Patient"}]}
      }
      """

      File.write!(tmp_file, json)

      try do
        assert {:ok, dataset} = JSON.decode_file(tmp_file)
        assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "Test^Patient"
      after
        File.rm(tmp_file)
      end
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_read_error, :enoent}} = JSON.decode_file("nonexistent.json")
    end
  end

  describe "roundtrip" do
    test "JSON export and import roundtrip preserves data" do
      {:ok, original} = Dcmix.read_file(@valid_dcm)

      # Export to JSON
      {:ok, json} = Dcmix.to_json(original)

      # Import from JSON
      {:ok, reimported} = JSON.decode(json)

      # Key attributes should match
      assert DataSet.get_string(reimported, {0x0010, 0x0010}) ==
               DataSet.get_string(original, {0x0010, 0x0010})

      assert DataSet.get_string(reimported, {0x0010, 0x0020}) ==
               DataSet.get_string(original, {0x0010, 0x0020})
    end
  end

  describe "edge cases" do
    test "handles invalid tag string" do
      json = """
      {
        "invalid": {"vr": "PN", "Value": ["test"]}
      }
      """

      # Should not crash, just skip invalid entries
      assert {:ok, dataset} = JSON.decode(json)
      assert Enum.empty?(dataset)
    end

    test "handles empty sequence" do
      json = """
      {
        "00081115": {"vr": "SQ"}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      element = DataSet.get(dataset, {0x0008, 0x1115})
      assert element.vr == :SQ
      assert element.value == []
    end

    test "handles person name with structured components" do
      json = """
      {
        "00100010": {"vr": "PN", "Value": [{"Alphabetic": {"FamilyName": "Doe", "GivenName": "John", "MiddleName": "Q", "NamePrefix": "Dr", "NameSuffix": "Jr"}}]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "Doe^John^Q^Dr^Jr"
    end

    test "handles person name with plain string in Alphabetic" do
      json = """
      {
        "00100010": {"vr": "PN", "Value": [{"Alphabetic": "Smith^Jane"}]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "Smith^Jane"
    end

    test "handles person name as plain string" do
      json = """
      {
        "00100010": {"vr": "PN", "Value": ["Plain^Name"]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "Plain^Name"
    end

    test "handles multiple AT values" do
      json = """
      {
        "00209165": {"vr": "AT", "Value": ["00100010", "00100020"]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      value = DataSet.get_value(dataset, {0x0020, 0x9165})
      assert value == [{0x0010, 0x0010}, {0x0010, 0x0020}]
    end

    test "handles multiple numeric values" do
      json = """
      {
        "00280010": {"vr": "US", "Value": [100, 200, 300]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_value(dataset, {0x0028, 0x0010}) == [100, 200, 300]
    end

    test "handles DS with nil values" do
      json = """
      {
        "00181050": {"vr": "DS", "Value": [null, 1.5]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_string(dataset, {0x0018, 0x1050}) == "\\1.5"
    end

    test "handles invalid base64 in InlineBinary" do
      json = """
      {
        "7FE00010": {"vr": "OW", "InlineBinary": "!!!invalid!!!"}
      }
      """

      # Should not crash, but the value will be an error
      assert {:ok, dataset} = JSON.decode(json)
      # The element should be skipped due to invalid base64
      assert DataSet.get(dataset, {0x7FE0, 0x0010}) == nil
    end

    test "handles non-map entry gracefully" do
      # This tests the parse_entry/1 catch-all clause
      json = """
      {
        "00100010": "not a map"
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      # Invalid entries should be skipped
      assert Enum.empty?(dataset)
    end

    test "handles missing vr field" do
      json = """
      {
        "00100010": {"Value": ["test"]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      element = DataSet.get(dataset, {0x0010, 0x0010})
      # Should still parse with nil VR
      assert element != nil
    end

    test "handles single value being simplified" do
      json = """
      {
        "00100020": {"vr": "LO", "Value": ["SingleValue"]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_string(dataset, {0x0010, 0x0020}) == "SingleValue"
    end

    test "handles float numeric values" do
      json = """
      {
        "00180050": {"vr": "FD", "Value": [1.5, 2.5]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_value(dataset, {0x0018, 0x0050}) == [1.5, 2.5]
    end

    test "handles signed integer values" do
      json = """
      {
        "00189219": {"vr": "SS", "Value": [-100, 100]}
      }
      """

      assert {:ok, dataset} = JSON.decode(json)
      assert DataSet.get_value(dataset, {0x0018, 0x9219}) == [-100, 100]
    end
  end
end
