defmodule DcmixTest do
  use ExUnit.Case
  doctest Dcmix

  @fixtures_path "test/fixtures"

  describe "Tag" do
    test "creates tag from group and element" do
      assert Dcmix.Tag.new(0x0010, 0x0010) == {0x0010, 0x0010}
    end

    test "parses tag from string" do
      assert {:ok, {0x0010, 0x0010}} = Dcmix.Tag.parse("(0010,0010)")
    end

    test "converts tag to string" do
      assert Dcmix.Tag.to_string({0x0010, 0x0010}) == "(0010,0010)"
    end

    test "identifies file meta tags" do
      assert Dcmix.Tag.file_meta?({0x0002, 0x0010})
      refute Dcmix.Tag.file_meta?({0x0010, 0x0010})
    end

    test "identifies private tags" do
      assert Dcmix.Tag.private?({0x0009, 0x0010})
      refute Dcmix.Tag.private?({0x0010, 0x0010})
    end

    test "compares tags" do
      assert Dcmix.Tag.compare({0x0008, 0x0010}, {0x0010, 0x0010}) == :lt
      assert Dcmix.Tag.compare({0x0010, 0x0010}, {0x0008, 0x0010}) == :gt
      assert Dcmix.Tag.compare({0x0010, 0x0010}, {0x0010, 0x0010}) == :eq
    end
  end

  describe "VR" do
    test "parses VR from string" do
      assert {:ok, :PN} = Dcmix.VR.parse("PN")
      assert {:ok, :LO} = Dcmix.VR.parse("LO")
    end

    test "converts VR to string" do
      assert Dcmix.VR.to_string(:PN) == "PN"
      assert Dcmix.VR.to_string(:LO) == "LO"
    end

    test "identifies long length VRs" do
      assert Dcmix.VR.long_length?(:OB)
      assert Dcmix.VR.long_length?(:SQ)
      refute Dcmix.VR.long_length?(:PN)
      refute Dcmix.VR.long_length?(:LO)
    end
  end

  describe "Dictionary" do
    test "looks up tag by tuple" do
      {:ok, result} = Dcmix.Dictionary.lookup({0x0010, 0x0010})
      assert result.keyword == "PatientName"
      assert result.vr == :PN
    end

    test "looks up tag by keyword" do
      tag = Dcmix.Dictionary.tag("PatientName")
      assert tag == {0x0010, 0x0010}
    end

    test "returns keyword for known tag" do
      assert Dcmix.Dictionary.keyword({0x0010, 0x0010}) == "PatientName"
      assert Dcmix.Dictionary.keyword({0x0010, 0x0020}) == "PatientID"
    end

    test "returns VR for known tag" do
      assert Dcmix.Dictionary.vr({0x0010, 0x0010}) == :PN
      assert Dcmix.Dictionary.vr({0x0008, 0x0060}) == :CS
    end
  end

  describe "DataSet" do
    test "creates empty dataset" do
      ds = Dcmix.DataSet.new()
      assert Dcmix.DataSet.size(ds) == 0
    end

    test "puts and gets elements" do
      ds =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")

      element = Dcmix.DataSet.get(ds, {0x0010, 0x0010})
      assert element != nil
      assert element.value == "Doe^John"
    end

    test "deletes elements" do
      ds =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")
        |> Dcmix.DataSet.delete({0x0010, 0x0010})

      assert Dcmix.DataSet.get(ds, {0x0010, 0x0010}) == nil
    end

    test "merges datasets" do
      ds1 =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")

      ds2 =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0010, 0x0020}, :LO, "12345")

      merged = Dcmix.DataSet.merge(ds1, ds2)
      assert Dcmix.DataSet.size(merged) == 2
    end
  end

  describe "Parser" do
    test "parses DICOM file" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        assert {:ok, dataset} = Dcmix.read_file(file)
        assert %Dcmix.DataSet{} = dataset

        # Should have some elements
        assert Dcmix.DataSet.size(dataset) > 0
      end
    end

    test "parses implicit VR file" do
      file = Path.join(@fixtures_path, "2_ORIGINAL.dcm")

      if File.exists?(file) do
        assert {:ok, dataset} = Dcmix.read_file(file)
        assert %Dcmix.DataSet{} = dataset
      end
    end

    test "returns error for non-existent file" do
      assert {:error, _reason} = Dcmix.read_file("nonexistent.dcm")
    end
  end

  describe "Export.Text" do
    test "dumps dataset to text" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        {:ok, dataset} = Dcmix.read_file(file)
        text = Dcmix.dump(dataset)

        assert is_binary(text)
        assert String.length(text) > 0
        # Should contain tag format
        assert String.contains?(text, "(")
      end
    end
  end

  describe "Export.JSON" do
    test "exports dataset to JSON" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        {:ok, dataset} = Dcmix.read_file(file)
        {:ok, json} = Dcmix.to_json(dataset)

        assert is_binary(json)
        # Should be valid JSON
        assert {:ok, _map} = Jason.decode(json)
      end
    end

    test "exports with pretty formatting" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        {:ok, dataset} = Dcmix.read_file(file)
        {:ok, json} = Dcmix.to_json(dataset, pretty: true)

        # Pretty JSON should have newlines
        assert String.contains?(json, "\n")
      end
    end
  end

  describe "Export.XML" do
    test "exports dataset to XML" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        {:ok, dataset} = Dcmix.read_file(file)
        {:ok, xml} = Dcmix.to_xml(dataset)

        assert is_binary(xml)
        # Should be valid XML
        assert String.starts_with?(xml, "<?xml")
        assert String.contains?(xml, "NativeDicomModel")
      end
    end
  end

  describe "Writer.ExplicitVR" do
    alias Dcmix.{DataSet, DataElement}

    test "encodes DataSet value with :UN VR" do
      # Create a nested DataSet (like a sequence item)
      nested_ds =
        DataSet.new([
          DataElement.new({0x0008, 0x0100}, :SH, "CODE1"),
          DataElement.new({0x0008, 0x0102}, :SH, "SCHEME")
        ])

      # Create an element with :UN VR containing a DataSet
      element = DataElement.new({0x0040, 0xA043}, :UN, nested_ds)

      ds = DataSet.new([element])

      # Should not raise - this was the bug we fixed
      binary = Dcmix.Writer.ExplicitVR.encode(ds)

      assert is_binary(binary)
      assert byte_size(binary) > 0
    end

    test "encodes list of DataSets with :UN VR" do
      # Create nested DataSets (like sequence items)
      item1 =
        DataSet.new([
          DataElement.new({0x0008, 0x0100}, :SH, "CODE1")
        ])

      item2 =
        DataSet.new([
          DataElement.new({0x0008, 0x0100}, :SH, "CODE2")
        ])

      # Create an element with :UN VR containing a list of DataSets
      element = DataElement.new({0x0040, 0xA043}, :UN, [item1, item2])

      ds = DataSet.new([element])

      # Should not raise - this was the bug we fixed
      binary = Dcmix.Writer.ExplicitVR.encode(ds)

      assert is_binary(binary)
      assert byte_size(binary) > 0
    end
  end

  describe "Main API" do
    test "get_string retrieves string value" do
      ds =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")

      assert Dcmix.get_string(ds, {0x0010, 0x0010}) == "Doe^John"
    end

    test "get_string with keyword" do
      ds =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")

      assert Dcmix.get_string(ds, "PatientName") == "Doe^John"
    end

    test "put adds element to dataset" do
      ds = Dcmix.new()
      ds = Dcmix.put(ds, {0x0010, 0x0010}, :PN, "Doe^John")

      assert Dcmix.get_string(ds, {0x0010, 0x0010}) == "Doe^John"
    end

    test "delete removes element from dataset" do
      ds =
        Dcmix.new()
        |> Dcmix.put({0x0010, 0x0010}, :PN, "Doe^John")
        |> Dcmix.delete({0x0010, 0x0010})

      assert Dcmix.get(ds, {0x0010, 0x0010}) == nil
    end
  end
end
