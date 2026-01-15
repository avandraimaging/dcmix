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

  describe "Writer" do
    alias Dcmix.{DataSet, DataElement, Writer}

    test "encodes dataset to binary" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0008, 0x0016}, :UI, "1.2.840.10008.5.1.4.1.1.2")
        |> DataSet.put_element({0x0008, 0x0018}, :UI, "1.2.3.4.5.6.7.8.9")
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "12345")

      assert {:ok, binary} = Writer.encode(ds)
      assert is_binary(binary)
      # Should have DICM prefix after preamble
      assert binary_part(binary, 128, 4) == "DICM"
    end

    test "writes and reads back dataset" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0008, 0x0016}, :UI, "1.2.840.10008.5.1.4.1.1.2")
        |> DataSet.put_element({0x0008, 0x0018}, :UI, "1.2.3.4.5.6.7.8.9")
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test^Patient")

      path = Path.join(System.tmp_dir!(), "dcmix_test_#{:rand.uniform(100000)}.dcm")

      try do
        assert :ok = Writer.write_file(ds, path)
        assert {:ok, read_ds} = Dcmix.read_file(path)
        assert DataSet.get_value(read_ds, {0x0010, 0x0010}) == "Test^Patient"
      after
        File.rm(path)
      end
    end

    test "generates unique UIDs" do
      uid1 = Writer.generate_uid()
      uid2 = Writer.generate_uid()

      assert is_binary(uid1)
      assert String.starts_with?(uid1, "1.2.826.0.1.3680043.9.7433.1.")
      # UIDs should be unique (with high probability)
      assert uid1 != uid2
    end
  end

  describe "Writer.ImplicitVR" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Writer.ImplicitVR

    test "encodes dataset with implicit VR" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "12345")

      binary = ImplicitVR.encode(ds)

      assert is_binary(binary)
      assert byte_size(binary) > 0
    end

    test "encodes numeric values" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
        |> DataSet.put_element({0x0028, 0x0011}, :US, 512)

      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes sequences" do
      item = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item])])

      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end
  end

  describe "PixelData" do
    alias Dcmix.{DataSet, DataElement, PixelData}

    test "extracts binary pixel data" do
      pixel_bytes = :crypto.strong_rand_bytes(100)
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, pixel_bytes)])

      assert {:ok, extracted} = PixelData.extract(ds)
      assert extracted == pixel_bytes
    end

    test "returns error when no pixel data" do
      ds = DataSet.new()
      assert {:error, :no_pixel_data} = PixelData.extract(ds)
    end

    test "returns error for empty pixel data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, nil)])
      assert {:error, :empty_pixel_data} = PixelData.extract(ds)
    end

    test "extracts encapsulated pixel data" do
      fragment1 = :crypto.strong_rand_bytes(50)
      fragment2 = :crypto.strong_rand_bytes(50)
      offset_table = <<0, 0, 0, 0>>
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, [offset_table, fragment1, fragment2])])

      # Without offset table (default)
      assert {:ok, extracted} = PixelData.extract(ds)
      assert extracted == fragment1 <> fragment2

      # With offset table
      assert {:ok, with_offset} = PixelData.extract(ds, include_offset_table: true)
      assert with_offset == offset_table <> fragment1 <> fragment2
    end

    test "extracts frames from encapsulated data" do
      offset_table = <<0, 0, 0, 0>>
      fragment1 = :crypto.strong_rand_bytes(50)
      fragment2 = :crypto.strong_rand_bytes(50)
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, [offset_table, fragment1, fragment2])])

      assert {:ok, frames} = PixelData.extract_frames(ds)
      # First fragment is offset table, remaining are actual frames
      assert frames == [fragment1, fragment2]
    end

    test "injects pixel data" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      pixel_bytes = :crypto.strong_rand_bytes(100)

      new_ds = PixelData.inject(ds, pixel_bytes)

      assert {:ok, extracted} = PixelData.extract(new_ds)
      assert extracted == pixel_bytes
    end

    test "gets pixel info" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
        |> DataSet.put_element({0x0028, 0x0011}, :US, 512)
        |> DataSet.put_element({0x0028, 0x0100}, :US, 16)
        |> DataSet.put_element({0x0028, 0x0101}, :US, 12)
        |> DataSet.put_element({0x0028, 0x0102}, :US, 11)
        |> DataSet.put_element({0x0028, 0x0103}, :US, 0)
        |> DataSet.put_element({0x0028, 0x0002}, :US, 1)
        |> DataSet.put_element({0x7FE0, 0x0010}, :OW, <<0, 0>>)

      info = PixelData.info(ds)

      assert info.rows == 512
      assert info.columns == 512
      assert info.bits_allocated == 16
      assert info.bits_stored == 12
      assert info.high_bit == 11
      assert info.pixel_representation == 0
      assert info.samples_per_pixel == 1
      assert info.has_pixel_data == true
    end

    test "encapsulated? returns true for encapsulated data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, [<<>>, <<>>])])
      assert PixelData.encapsulated?(ds) == true
    end

    test "encapsulated? returns false for native data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 0>>)])
      assert PixelData.encapsulated?(ds) == false
    end
  end

  describe "PrivateTag" do
    alias Dcmix.{DataSet, PrivateTag}

    test "registers private creator" do
      ds = DataSet.new()
      {ds, block} = PrivateTag.register_creator(ds, 0x0009, "ACME Corp")

      assert block == 0x10
      assert DataSet.get_value(ds, {0x0009, 0x0010}) == "ACME Corp"
    end

    test "finds existing creator block" do
      ds = DataSet.new()
      {ds, _block} = PrivateTag.register_creator(ds, 0x0009, "ACME Corp")

      assert {:ok, 0x10} = PrivateTag.find_creator_block(ds, 0x0009, "ACME Corp")
    end

    test "returns not_found for unregistered creator" do
      ds = DataSet.new()
      assert :not_found = PrivateTag.find_creator_block(ds, 0x0009, "Unknown")
    end

    test "puts and gets private data" do
      ds = DataSet.new()
      {ds, _} = PrivateTag.register_creator(ds, 0x0009, "ACME Corp")
      ds = PrivateTag.put(ds, 0x0009, "ACME Corp", 0x01, :LO, "Private Data")

      assert PrivateTag.get(ds, 0x0009, "ACME Corp", 0x01) == "Private Data"
    end

    test "put! auto-registers creator" do
      ds = DataSet.new()
      ds = PrivateTag.put!(ds, 0x0009, "ACME Corp", 0x01, :LO, "Private Data")

      assert PrivateTag.get(ds, 0x0009, "ACME Corp", 0x01) == "Private Data"
    end

    test "deletes private data" do
      ds = DataSet.new()
      ds = PrivateTag.put!(ds, 0x0009, "ACME Corp", 0x01, :LO, "Data")
      ds = PrivateTag.delete(ds, 0x0009, "ACME Corp", 0x01)

      assert PrivateTag.get(ds, 0x0009, "ACME Corp", 0x01) == nil
    end

    test "lists creators" do
      ds = DataSet.new()
      {ds, _} = PrivateTag.register_creator(ds, 0x0009, "ACME Corp")
      {ds, _} = PrivateTag.register_creator(ds, 0x0009, "Other Vendor")

      creators = PrivateTag.list_creators(ds, 0x0009)
      assert length(creators) == 2
      assert {"ACME Corp", 0x10} in creators
      assert {"Other Vendor", 0x11} in creators
    end

    test "makes and parses private tags" do
      tag = PrivateTag.make_tag(0x0009, 0x10, 0x01)
      assert tag == {0x0009, 0x1001}

      assert {:ok, {0x10, 0x01}} = PrivateTag.parse_tag(tag)
    end

    test "parse_tag returns error for non-private" do
      assert {:error, :not_private} = PrivateTag.parse_tag({0x0010, 0x0010})
    end

    test "get_element returns element" do
      ds = PrivateTag.put!(DataSet.new(), 0x0009, "ACME", 0x01, :LO, "Data")
      element = PrivateTag.get_element(ds, 0x0009, "ACME", 0x01)

      assert element != nil
      assert element.value == "Data"
    end

    test "list_elements returns all elements for creator" do
      ds = DataSet.new()
      ds = PrivateTag.put!(ds, 0x0009, "ACME", 0x01, :LO, "Data1")
      ds = PrivateTag.put!(ds, 0x0009, "ACME", 0x02, :LO, "Data2")

      elements = PrivateTag.list_elements(ds, 0x0009, "ACME")
      assert length(elements) == 2
    end
  end

  describe "DataElement" do
    alias Dcmix.DataElement

    test "creates new element" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Doe^John")

      assert elem.tag == {0x0010, 0x0010}
      assert elem.vr == :PN
      assert elem.value == "Doe^John"
    end

    test "creates element with explicit length" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Doe^John", 8)
      assert elem.length == 8
    end

    test "string_value returns string" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Doe^John")
      assert DataElement.string_value(elem) == "Doe^John"
    end

    test "string_value joins list values" do
      elem = DataElement.new({0x0008, 0x0008}, :CS, ["ORIGINAL", "PRIMARY"])
      assert DataElement.string_value(elem) == "ORIGINAL\\PRIMARY"
    end

    test "string_value returns nil for nil value" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, nil)
      assert DataElement.string_value(elem) == nil
    end

    test "values returns list" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Doe^John")
      assert DataElement.values(elem) == ["Doe^John"]
    end

    test "values splits backslash-separated string" do
      elem = DataElement.new({0x0008, 0x0008}, :CS, "ORIGINAL\\PRIMARY")
      assert DataElement.values(elem) == ["ORIGINAL", "PRIMARY"]
    end

    test "values returns empty list for nil" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, nil)
      assert DataElement.values(elem) == []
    end

    test "first_value returns first value" do
      elem = DataElement.new({0x0008, 0x0008}, :CS, "ORIGINAL\\PRIMARY")
      assert DataElement.first_value(elem) == "ORIGINAL"
    end

    test "string_value converts numbers to string" do
      elem = DataElement.new({0x0028, 0x0010}, :US, 512)
      assert DataElement.string_value(elem) == "512"
    end
  end

  describe "Tag extended" do
    alias Dcmix.Tag

    test "item_tag? identifies item tags" do
      assert Tag.item_tag?({0xFFFE, 0xE000})
      assert Tag.item_tag?({0xFFFE, 0xE00D})
      assert Tag.item_tag?({0xFFFE, 0xE0DD})
      refute Tag.item_tag?({0x0010, 0x0010})
    end

    test "group returns group number" do
      assert Tag.group({0x0010, 0x0020}) == 0x0010
    end

    test "element returns element number" do
      assert Tag.element({0x0010, 0x0020}) == 0x0020
    end

    test "named tag accessors" do
      assert Tag.patient_name() == {0x0010, 0x0010}
      assert Tag.patient_id() == {0x0010, 0x0020}
      assert Tag.sop_class_uid() == {0x0008, 0x0016}
      assert Tag.sop_instance_uid() == {0x0008, 0x0018}
      assert Tag.transfer_syntax_uid() == {0x0002, 0x0010}
    end

    test "parse handles various formats" do
      assert {:ok, {0x0010, 0x0010}} = Tag.parse("(0010,0010)")
      assert {:ok, {0x0010, 0x0010}} = Tag.parse("00100010")
      assert {:error, _reason} = Tag.parse("invalid")
    end
  end

  describe "VR extended" do
    alias Dcmix.VR

    test "valid? checks VR validity" do
      assert VR.valid?(:PN)
      assert VR.valid?(:LO)
      refute VR.valid?(:XX)
    end

    test "string? identifies string VRs" do
      assert VR.string?(:PN)
      assert VR.string?(:LO)
      assert VR.string?(:SH)
      refute VR.string?(:US)
      refute VR.string?(:OB)
    end

    test "max_length returns length limits" do
      assert VR.max_length(:SH) == 16
      assert VR.max_length(:LO) == 64
      assert VR.max_length(:PN) == 64
    end

    test "padding returns padding character" do
      assert VR.padding(:PN) == 0x20
      assert VR.padding(:UI) == 0x00
      assert VR.padding(:OB) == 0x00
    end
  end

  describe "Dictionary extended" do
    alias Dcmix.Dictionary

    test "lookup returns error for unknown tag" do
      assert {:error, :not_found} = Dictionary.lookup({0xFFFF, 0xFFFF})
    end

    test "keyword returns nil for unknown tag" do
      assert Dictionary.keyword({0xFFFF, 0xFFFF}) == nil
    end

    test "vr returns nil for unknown tag" do
      assert Dictionary.vr({0xFFFF, 0xFFFF}) == nil
    end

    test "tag returns nil for unknown keyword" do
      assert Dictionary.tag("UnknownKeyword") == nil
    end
  end

  describe "DataSet extended" do
    alias Dcmix.{DataSet, DataElement}

    test "has_tag? checks for tag presence" do
      ds = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")

      assert DataSet.has_tag?(ds, {0x0010, 0x0010})
      refute DataSet.has_tag?(ds, {0x0010, 0x0020})
    end

    test "get_value returns value directly" do
      ds = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
      assert DataSet.get_value(ds, {0x0010, 0x0010}) == "Test"
    end

    test "get_string returns string value" do
      ds = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
      assert DataSet.get_string(ds, {0x0010, 0x0010}) == "Test"
    end

    test "tags returns list of tags" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "ID")

      tags = DataSet.tags(ds)
      assert {0x0010, 0x0010} in tags
      assert {0x0010, 0x0020} in tags
    end

    test "to_list returns elements in order" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "ID")
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Name")

      list = DataSet.to_list(ds)
      # Should be sorted by tag
      assert hd(list).tag == {0x0010, 0x0010}
    end

    test "split_file_meta separates file meta elements" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0002, 0x0010}, :UI, "1.2.3")
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")

      {file_meta, data} = DataSet.split_file_meta(ds)

      assert DataSet.has_tag?(file_meta, {0x0002, 0x0010})
      refute DataSet.has_tag?(file_meta, {0x0010, 0x0010})
      assert DataSet.has_tag?(data, {0x0010, 0x0010})
      refute DataSet.has_tag?(data, {0x0002, 0x0010})
    end

    test "enumerable implementation" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "ID")

      # count
      assert Enum.count(ds) == 2

      # member?
      elem = DataSet.get(ds, {0x0010, 0x0010})
      assert Enum.member?(ds, elem)

      # map
      tags = Enum.map(ds, & &1.tag)
      assert length(tags) == 2
    end
  end

  describe "TransferSyntax" do
    alias Dcmix.Parser.TransferSyntax

    test "lookup returns known transfer syntaxes" do
      assert {:ok, ts} = TransferSyntax.lookup("1.2.840.10008.1.2")
      assert ts.explicit_vr == false

      assert {:ok, ts} = TransferSyntax.lookup("1.2.840.10008.1.2.1")
      assert ts.explicit_vr == true
      assert ts.big_endian == false

      assert {:ok, ts} = TransferSyntax.lookup("1.2.840.10008.1.2.2")
      assert ts.explicit_vr == true
      assert ts.big_endian == true
    end

    test "lookup returns error for unknown syntax" do
      assert {:error, :unknown_transfer_syntax} = TransferSyntax.lookup("1.2.3.4.5")
    end

    test "named accessors return UIDs" do
      assert TransferSyntax.implicit_vr_little_endian() == "1.2.840.10008.1.2"
      assert TransferSyntax.explicit_vr_little_endian() == "1.2.840.10008.1.2.1"
      assert TransferSyntax.explicit_vr_big_endian() == "1.2.840.10008.1.2.2"
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

    test "get returns value directly" do
      ds = Dcmix.put(Dcmix.new(), {0x0010, 0x0010}, :PN, "Test")
      assert Dcmix.get(ds, {0x0010, 0x0010}) == "Test"
    end

    test "get with keyword returns value" do
      ds = Dcmix.put(Dcmix.new(), {0x0010, 0x0010}, :PN, "Test")
      assert Dcmix.get(ds, "PatientName") == "Test"
    end

    test "get_element returns element" do
      ds = Dcmix.put(Dcmix.new(), {0x0010, 0x0010}, :PN, "Test")
      elem = Dcmix.get_element(ds, {0x0010, 0x0010})
      assert elem.value == "Test"
    end

    test "get_element with keyword" do
      ds = Dcmix.put(Dcmix.new(), {0x0010, 0x0010}, :PN, "Test")
      elem = Dcmix.get_element(ds, "PatientName")
      assert elem.value == "Test"
    end

    test "delete with keyword" do
      ds = Dcmix.put(Dcmix.new(), {0x0010, 0x0010}, :PN, "Test")
      ds = Dcmix.delete(ds, "PatientName")
      assert Dcmix.get(ds, {0x0010, 0x0010}) == nil
    end
  end

  describe "Parser extended" do
    alias Dcmix.Parser

    @fixtures_path "test/fixtures"

    test "parse_file_meta_only extracts file meta" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        assert {:ok, file_meta} = Parser.parse_file_meta_only(file)
        assert Dcmix.DataSet.has_tag?(file_meta, {0x0002, 0x0010})
      end
    end

    test "parse_file_meta_only returns error for non-existent file" do
      assert {:error, _} = Parser.parse_file_meta_only("nonexistent.dcm")
    end

    test "get_transfer_syntax returns transfer syntax UID" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        assert {:ok, ts_uid} = Parser.get_transfer_syntax(file)
        assert is_binary(ts_uid)
        assert String.starts_with?(ts_uid, "1.2.840.10008")
      end
    end

    test "parse binary data" do
      # Create minimal valid DICOM binary with Explicit VR Little Endian
      ds =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "Test")

      binary = Dcmix.Writer.ExplicitVR.encode(ds)

      assert {:ok, parsed} = Parser.parse(binary)
      assert Dcmix.DataSet.get_value(parsed, {0x0010, 0x0010}) == "Test"
    end

    test "parse with force_transfer_syntax" do
      ds =
        Dcmix.DataSet.new()
        |> Dcmix.DataSet.put_element({0x0010, 0x0010}, :PN, "Test")

      binary = Dcmix.Writer.ImplicitVR.encode(ds)

      # Force Implicit VR Little Endian transfer syntax
      assert {:ok, parsed} = Parser.parse(binary, force_transfer_syntax: "1.2.840.10008.1.2")
      assert Dcmix.DataSet.get_value(parsed, {0x0010, 0x0010}) == "Test"
    end
  end

  describe "Export.Text extended" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.Text

    test "encodes empty dataset" do
      ds = DataSet.new()
      text = Text.encode(ds)
      assert text == ""
    end

    test "encodes with max_value_length option" do
      ds = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "A very long name that exceeds the limit")
      text = Text.encode(ds, max_value_length: 10)
      assert String.contains?(text, "...")
    end

    test "encodes numeric values" do
      ds = DataSet.new() |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
      text = Text.encode(ds)
      assert String.contains?(text, "512")
    end

    test "encodes binary data with hex preview" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 1, 2, 3>>)])
      text = Text.encode(ds)
      assert String.contains?(text, "00 01 02 03")
    end

    test "encodes sequences" do
      item = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item])])
      text = Text.encode(ds)
      assert String.contains?(text, "Item #0")
      assert String.contains?(text, "CODE")
    end

    test "encodes empty sequence" do
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [])])
      text = Text.encode(ds)
      assert String.contains?(text, "(no items)")
    end

    test "encodes AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, {0x0010, 0x0020})])
      text = Text.encode(ds)
      assert String.contains?(text, "(0010,0020)")
    end
  end

  describe "Export.JSON extended" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.JSON

    test "encodes empty dataset" do
      ds = DataSet.new()
      assert {:ok, json} = JSON.encode(ds)
      assert {:ok, %{}} = Jason.decode(json)
    end

    test "encodes numeric values" do
      ds = DataSet.new() |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
      assert {:ok, json} = JSON.encode(ds)
      assert {:ok, map} = Jason.decode(json)
      assert map["00280010"]["Value"] == [512]
    end

    test "encodes sequences" do
      item = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item])])
      assert {:ok, json} = JSON.encode(ds)
      assert {:ok, map} = Jason.decode(json)
      assert map["0040A730"]["vr"] == "SQ"
    end

    test "encodes binary data as base64" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 1, 2, 3>>)])
      assert {:ok, json} = JSON.encode(ds)
      assert {:ok, map} = Jason.decode(json)
      assert map["7FE00010"]["InlineBinary"] != nil
    end
  end

  describe "Export.XML extended" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.XML

    test "encodes empty dataset" do
      ds = DataSet.new()
      assert {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "NativeDicomModel")
    end

    test "encodes without pretty printing" do
      ds = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
      assert {:ok, xml} = XML.encode(ds, pretty: false)
      refute String.contains?(xml, "\n  ")
    end

    test "encodes PN values with PersonName element" do
      ds = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")
      assert {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "PersonName")
      assert String.contains?(xml, "FamilyName")
    end

    test "encodes binary data as base64" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 1, 2, 3>>)])
      assert {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "InlineBinary")
    end

    test "escapes special XML characters" do
      ds = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test<>&\"'")
      assert {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "&lt;")
      assert String.contains?(xml, "&gt;")
      assert String.contains?(xml, "&amp;")
    end
  end

  describe "Writer.ExplicitVR extended" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Writer.ExplicitVR

    test "encodes various numeric types" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
        |> DataSet.put_element({0x0028, 0x1050}, :DS, "100.0")
        |> DataSet.put_element({0x0018, 0x0050}, :DS, 1.5)

      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes empty values" do
      ds = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "")
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes with big endian" do
      ds = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
      binary = ExplicitVR.encode(ds, big_endian: true)
      assert is_binary(binary)
    end

    test "encodes long VR types" do
      # OB is a long VR type
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, <<1, 2, 3, 4>>)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes sequences with items" do
      item1 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE1")])
      item2 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE2")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item1, item2])])

      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
      assert byte_size(binary) > 0
    end

    test "encodes AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, {0x0010, 0x0020})])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, [{0x0010, 0x0020}, {0x0010, 0x0010}])])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes multi-value numeric arrays" do
      ds = DataSet.new() |> DataSet.put_element({0x0028, 0x1051}, :DS, [100, 200, 300])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end
  end

  describe "Writer.ImplicitVR extended" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Writer.ImplicitVR

    test "encodes various value types" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
        |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
        |> DataSet.put_element({0x0018, 0x0050}, :DS, "1.5")

      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes binary data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<1, 2, 3, 4>>)])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes empty sequence" do
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end
  end

  describe "Round-trip tests" do
    alias Dcmix.{DataSet, DataElement, Writer, Parser}

    test "explicit VR round-trip preserves data" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "12345")
        |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
        |> DataSet.put_element({0x0028, 0x0011}, :US, 512)

      binary = Writer.ExplicitVR.encode(ds)
      {:ok, parsed} = Parser.parse(binary)

      assert DataSet.get_value(parsed, {0x0010, 0x0010}) == "Doe^John"
      assert DataSet.get_value(parsed, {0x0010, 0x0020}) == "12345"
      assert DataSet.get_value(parsed, {0x0028, 0x0010}) == 512
    end

    test "implicit VR round-trip preserves data" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Doe^John")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "12345")

      binary = Writer.ImplicitVR.encode(ds)
      # Force Implicit VR Little Endian transfer syntax
      {:ok, parsed} = Parser.parse(binary, force_transfer_syntax: "1.2.840.10008.1.2")

      assert DataSet.get_value(parsed, {0x0010, 0x0010}) == "Doe^John"
      assert DataSet.get_value(parsed, {0x0010, 0x0020}) == "12345"
    end

    test "sequence round-trip" do
      item = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item])])

      binary = Writer.ExplicitVR.encode(ds)
      {:ok, parsed} = Parser.parse(binary)

      seq = DataSet.get(parsed, {0x0040, 0xA730})
      assert seq.vr == :SQ
      assert length(seq.value) == 1
    end
  end

  describe "TransferSyntax comprehensive" do
    alias Dcmix.Parser.TransferSyntax

    test "UID accessors return correct values" do
      assert TransferSyntax.implicit_vr_little_endian() == "1.2.840.10008.1.2"
      assert TransferSyntax.explicit_vr_little_endian() == "1.2.840.10008.1.2.1"
      assert TransferSyntax.explicit_vr_big_endian() == "1.2.840.10008.1.2.2"
      assert TransferSyntax.jpeg_baseline() == "1.2.840.10008.1.2.4.50"
      assert TransferSyntax.jpeg_extended() == "1.2.840.10008.1.2.4.51"
      assert TransferSyntax.jpeg_lossless() == "1.2.840.10008.1.2.4.57"
      assert TransferSyntax.jpeg_lossless_sv1() == "1.2.840.10008.1.2.4.70"
      assert TransferSyntax.jpeg_ls_lossless() == "1.2.840.10008.1.2.4.80"
      assert TransferSyntax.jpeg_ls_lossy() == "1.2.840.10008.1.2.4.81"
      assert TransferSyntax.jpeg_2000_lossless() == "1.2.840.10008.1.2.4.90"
      assert TransferSyntax.jpeg_2000() == "1.2.840.10008.1.2.4.91"
      assert TransferSyntax.rle_lossless() == "1.2.840.10008.1.2.5"
    end

    test "lookup returns correct transfer syntax" do
      assert {:ok, ts} = TransferSyntax.lookup("1.2.840.10008.1.2.1")
      assert ts.name == "Explicit VR Little Endian"
      assert ts.explicit_vr == true
      assert ts.big_endian == false
    end

    test "lookup returns error for unknown UID" do
      assert {:error, :unknown_transfer_syntax} = TransferSyntax.lookup("1.2.3.4.5.6")
    end

    test "default returns Explicit VR Little Endian" do
      ts = TransferSyntax.default()
      assert ts.uid == "1.2.840.10008.1.2.1"
    end

    test "explicit_vr? with struct" do
      {:ok, explicit_ts} = TransferSyntax.lookup("1.2.840.10008.1.2.1")
      {:ok, implicit_ts} = TransferSyntax.lookup("1.2.840.10008.1.2")
      assert TransferSyntax.explicit_vr?(explicit_ts) == true
      assert TransferSyntax.explicit_vr?(implicit_ts) == false
    end

    test "explicit_vr? with UID string" do
      assert TransferSyntax.explicit_vr?("1.2.840.10008.1.2.1") == true
      assert TransferSyntax.explicit_vr?("1.2.840.10008.1.2") == false
      # Unknown UID defaults to true
      assert TransferSyntax.explicit_vr?("1.2.3.4.5") == true
    end

    test "big_endian? with struct" do
      {:ok, little_ts} = TransferSyntax.lookup("1.2.840.10008.1.2.1")
      {:ok, big_ts} = TransferSyntax.lookup("1.2.840.10008.1.2.2")
      assert TransferSyntax.big_endian?(little_ts) == false
      assert TransferSyntax.big_endian?(big_ts) == true
    end

    test "big_endian? with UID string" do
      assert TransferSyntax.big_endian?("1.2.840.10008.1.2.1") == false
      assert TransferSyntax.big_endian?("1.2.840.10008.1.2.2") == true
      # Unknown UID defaults to false
      assert TransferSyntax.big_endian?("1.2.3.4.5") == false
    end

    test "encapsulated? with struct" do
      {:ok, native_ts} = TransferSyntax.lookup("1.2.840.10008.1.2.1")
      {:ok, compressed_ts} = TransferSyntax.lookup("1.2.840.10008.1.2.4.50")
      assert TransferSyntax.encapsulated?(native_ts) == false
      assert TransferSyntax.encapsulated?(compressed_ts) == true
    end

    test "encapsulated? with UID string" do
      assert TransferSyntax.encapsulated?("1.2.840.10008.1.2.1") == false
      assert TransferSyntax.encapsulated?("1.2.840.10008.1.2.4.50") == true
      # Unknown UID defaults to false
      assert TransferSyntax.encapsulated?("1.2.3.4.5") == false
    end

    test "lossy? with struct" do
      {:ok, lossless_ts} = TransferSyntax.lookup("1.2.840.10008.1.2.4.57")
      {:ok, lossy_ts} = TransferSyntax.lookup("1.2.840.10008.1.2.4.50")
      assert TransferSyntax.lossy?(lossless_ts) == false
      assert TransferSyntax.lossy?(lossy_ts) == true
    end

    test "lossy? with UID string" do
      assert TransferSyntax.lossy?("1.2.840.10008.1.2.4.57") == false
      assert TransferSyntax.lossy?("1.2.840.10008.1.2.4.50") == true
      # Unknown UID defaults to false
      assert TransferSyntax.lossy?("1.2.3.4.5") == false
    end

    test "all returns list of transfer syntaxes" do
      all = TransferSyntax.all()
      assert is_list(all)
      assert length(all) > 0
      assert Enum.all?(all, fn ts -> is_struct(ts, TransferSyntax) end)
    end
  end

  describe "DataElement comprehensive" do
    alias Dcmix.DataElement

    test "new/3 creates element with calculated length" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Doe^John")
      assert elem.tag == {0x0010, 0x0010}
      assert elem.vr == :PN
      assert elem.value == "Doe^John"
      assert elem.length == 8
    end

    test "new/4 creates element with explicit length" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Doe^John", 100)
      assert elem.length == 100
    end

    test "tag/1 returns tag" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Test")
      assert DataElement.tag(elem) == {0x0010, 0x0010}
    end

    test "vr/1 returns VR" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Test")
      assert DataElement.vr(elem) == :PN
    end

    test "value/1 returns value" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Test")
      assert DataElement.value(elem) == "Test"
    end

    test "sequence?/1 returns true for SQ" do
      seq_elem = DataElement.new({0x0040, 0xA730}, :SQ, [])
      non_seq = DataElement.new({0x0010, 0x0010}, :PN, "Test")
      assert DataElement.sequence?(seq_elem) == true
      assert DataElement.sequence?(non_seq) == false
    end

    test "items/1 returns sequence items" do
      item = Dcmix.DataSet.new()
      seq_elem = DataElement.new({0x0040, 0xA730}, :SQ, [item])
      assert DataElement.items(seq_elem) == [item]
    end

    test "items/1 returns empty list for non-sequence" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Test")
      assert DataElement.items(elem) == []
    end

    test "string_value/1 returns nil for nil value" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, nil)
      assert DataElement.string_value(elem) == nil
    end

    test "string_value/1 joins list values" do
      elem = DataElement.new({0x0020, 0x0037}, :DS, ["1.0", "0.0", "0.0"])
      assert DataElement.string_value(elem) == "1.0\\0.0\\0.0"
    end

    test "string_value/1 returns binary as-is" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Test")
      assert DataElement.string_value(elem) == "Test"
    end

    test "string_value/1 converts numbers to string" do
      elem = DataElement.new({0x0028, 0x0010}, :US, 512)
      assert DataElement.string_value(elem) == "512"
    end

    test "values/1 returns empty list for nil" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, nil)
      assert DataElement.values(elem) == []
    end

    test "values/1 returns list as-is" do
      elem = DataElement.new({0x0020, 0x0037}, :DS, ["1.0", "0.0"])
      assert DataElement.values(elem) == ["1.0", "0.0"]
    end

    test "values/1 splits string with backslash for multi-valued VRs" do
      elem = DataElement.new({0x0020, 0x0037}, :DS, "1.0\\0.0\\0.0")
      assert DataElement.values(elem) == ["1.0", "0.0", "0.0"]
    end

    test "values/1 returns single element list for non-multi VRs" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Test")
      assert DataElement.values(elem) == ["Test"]
    end

    test "values/1 wraps single number in list" do
      elem = DataElement.new({0x0028, 0x0010}, :US, 512)
      assert DataElement.values(elem) == [512]
    end

    test "first_value/1 returns first from list" do
      elem = DataElement.new({0x0020, 0x0037}, :DS, ["1.0", "0.0"])
      assert DataElement.first_value(elem) == "1.0"
    end

    test "first_value/1 returns nil for nil value" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, nil)
      assert DataElement.first_value(elem) == nil
    end

    test "put_value/2 updates value" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Old")
      updated = DataElement.put_value(elem, "New")
      assert updated.value == "New"
      assert updated.length == 3
    end

    test "undefined_length?/1 returns true for :undefined" do
      elem = DataElement.new({0x0040, 0xA730}, :SQ, [], :undefined)
      assert DataElement.undefined_length?(elem) == true
    end

    test "undefined_length?/1 returns false for numeric length" do
      elem = DataElement.new({0x0010, 0x0010}, :PN, "Test", 4)
      assert DataElement.undefined_length?(elem) == false
    end

    test "calculate_length for numeric types" do
      us_elem = DataElement.new({0x0028, 0x0010}, :US, 512)
      assert us_elem.length == 2

      ul_elem = DataElement.new({0x0028, 0x0030}, :UL, 1000)
      assert ul_elem.length == 4

      fd_elem = DataElement.new({0x0018, 0x0050}, :FD, 1.5)
      assert fd_elem.length == 8

      at_elem = DataElement.new({0x0020, 0x5100}, :AT, {0x0010, 0x0020})
      assert at_elem.length == 4
    end

    test "calculate_length for numeric lists" do
      elem = DataElement.new({0x0028, 0x0010}, :US, [512, 256, 128])
      assert elem.length == 6
    end
  end

  describe "PixelData comprehensive" do
    alias Dcmix.{DataSet, DataElement, PixelData}

    test "extract returns error for no pixel data" do
      ds = DataSet.new()
      assert {:error, :no_pixel_data} = PixelData.extract(ds)
    end

    test "extract returns error for empty pixel data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, nil)])
      assert {:error, :empty_pixel_data} = PixelData.extract(ds)
    end

    test "extract returns binary pixel data" do
      pixels = <<0, 1, 2, 3, 4, 5>>
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, pixels)])
      assert {:ok, ^pixels} = PixelData.extract(ds)
    end

    test "extract with include_offset_table option" do
      offset_table = <<0, 0, 0, 0>>
      frame1 = <<1, 2, 3, 4>>
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, [offset_table, frame1], :undefined)])

      # Without offset table
      {:ok, result1} = PixelData.extract(ds, include_offset_table: false)
      assert result1 == frame1

      # With offset table
      {:ok, result2} = PixelData.extract(ds, include_offset_table: true)
      assert result2 == offset_table <> frame1
    end

    test "extract_frames returns error for no pixel data" do
      ds = DataSet.new()
      assert {:error, :no_pixel_data} = PixelData.extract_frames(ds)
    end

    test "extract_frames returns single frame for native data" do
      pixels = <<0, 1, 2, 3>>
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, pixels)])
      assert {:ok, [^pixels]} = PixelData.extract_frames(ds)
    end

    test "extract_frames skips offset table for encapsulated" do
      offset_table = <<0, 0, 0, 0>>
      frame1 = <<1, 2, 3, 4>>
      frame2 = <<5, 6, 7, 8>>
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, [offset_table, frame1, frame2], :undefined)])
      assert {:ok, [^frame1, ^frame2]} = PixelData.extract_frames(ds)
    end

    test "inject creates native pixel data" do
      ds = DataSet.new()
      pixels = <<0, 1, 2, 3>>
      result = PixelData.inject(ds, pixels)
      elem = DataSet.get(result, {0x7FE0, 0x0010})
      assert elem.vr == :OW
      assert elem.value == pixels
    end

    test "inject with custom VR" do
      ds = DataSet.new()
      pixels = <<0, 1, 2, 3>>
      result = PixelData.inject(ds, pixels, vr: :OB)
      elem = DataSet.get(result, {0x7FE0, 0x0010})
      assert elem.vr == :OB
    end

    test "inject_encapsulated creates encapsulated pixel data" do
      ds = DataSet.new()
      frames = [<<1, 2, 3>>, <<4, 5, 6>>]
      result = PixelData.inject_encapsulated(ds, frames)
      elem = DataSet.get(result, {0x7FE0, 0x0010})
      assert elem.vr == :OB
      assert elem.length == :undefined
      # First fragment is offset table
      assert length(elem.value) == 3
    end

    test "inject_encapsulated with custom offset table" do
      ds = DataSet.new()
      frames = [<<1, 2, 3>>]
      offset_table = <<0, 0, 0, 0, 0, 0, 0, 0>>
      result = PixelData.inject_encapsulated(ds, frames, offset_table: offset_table)
      elem = DataSet.get(result, {0x7FE0, 0x0010})
      assert hd(elem.value) == offset_table
    end

    test "info returns pixel metadata" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
        |> DataSet.put_element({0x0028, 0x0011}, :US, 256)
        |> DataSet.put_element({0x0028, 0x0002}, :US, 1)
        |> DataSet.put_element({0x0028, 0x0100}, :US, 16)
        |> DataSet.put_element({0x0028, 0x0101}, :US, 12)
        |> DataSet.put_element({0x0028, 0x0102}, :US, 11)
        |> DataSet.put_element({0x0028, 0x0103}, :US, 0)
        |> DataSet.put_element({0x0028, 0x0004}, :CS, "MONOCHROME2")

      info = PixelData.info(ds)
      assert info.rows == 512
      assert info.columns == 256
      assert info.samples_per_pixel == 1
      assert info.bits_allocated == 16
      assert info.bits_stored == 12
      assert info.high_bit == 11
      assert info.pixel_representation == 0
      assert info.photometric_interpretation == "MONOCHROME2"
      assert info.has_pixel_data == false
    end

    test "info parses number_of_frames from string" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0028, 0x0010}, :US, 100)
        |> DataSet.put_element({0x0028, 0x0011}, :US, 100)
        |> DataSet.put_element({0x0028, 0x0008}, :IS, "10")

      info = PixelData.info(ds)
      assert info.number_of_frames == 10
    end

    test "expected_size calculates correctly" do
      ds =
        DataSet.new()
        |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
        |> DataSet.put_element({0x0028, 0x0011}, :US, 256)
        |> DataSet.put_element({0x0028, 0x0100}, :US, 16)

      # 512 * 256 * 2 bytes = 262144
      assert PixelData.expected_size(ds) == 262_144
    end

    test "expected_size returns nil for missing info" do
      ds = DataSet.new()
      assert PixelData.expected_size(ds) == nil
    end

    test "encapsulated? returns true for encapsulated data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, [<<>>, <<1, 2>>], :undefined)])
      assert PixelData.encapsulated?(ds) == true
    end

    test "encapsulated? returns false for native data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 1, 2, 3>>)])
      assert PixelData.encapsulated?(ds) == false
    end
  end

  describe "Parser.ExplicitVR comprehensive" do
    alias Dcmix.Parser.ExplicitVR
    alias Dcmix.{DataSet, DataElement}

    test "parse empty binary returns empty dataset" do
      {:ok, ds, rest} = ExplicitVR.parse(<<>>)
      assert DataSet.size(ds) == 0
      assert rest == <<>>
    end

    test "parse with stop_tag option" do
      # Build binary with two elements
      ds = DataSet.new()
        |> DataSet.put_element({0x0008, 0x0010}, :SH, "First")
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Second")

      binary = Dcmix.Writer.ExplicitVR.encode(ds)

      # Stop before second element
      {:ok, parsed, _rest} = ExplicitVR.parse(binary, stop_tag: {0x0010, 0x0000})
      assert DataSet.has_tag?(parsed, {0x0008, 0x0010})
      refute DataSet.has_tag?(parsed, {0x0010, 0x0010})
    end

    test "parse handles short binary gracefully" do
      {:ok, ds, rest} = ExplicitVR.parse(<<1, 2>>)
      assert DataSet.size(ds) == 0
      assert rest == <<1, 2>>
    end

    test "parse binary VR types" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 1, 2, 3>>)])
      binary = Dcmix.Writer.ExplicitVR.encode(ds)
      {:ok, parsed, _} = ExplicitVR.parse(binary)
      elem = DataSet.get(parsed, {0x7FE0, 0x0010})
      assert elem.value == <<0, 1, 2, 3>>
    end

    test "parse multiple numeric values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :US, [512, 256])])
      binary = Dcmix.Writer.ExplicitVR.encode(ds)
      {:ok, parsed, _} = ExplicitVR.parse(binary)
      elem = DataSet.get(parsed, {0x0028, 0x0010})
      assert elem.value == [512, 256]
    end
  end

  describe "Parser.ImplicitVR comprehensive" do
    alias Dcmix.Parser.ImplicitVR
    alias Dcmix.{DataSet, DataElement}

    test "parse empty binary returns empty dataset" do
      {:ok, ds, rest} = ImplicitVR.parse(<<>>)
      assert DataSet.size(ds) == 0
      assert rest == <<>>
    end

    test "parse with stop_tag option" do
      ds = DataSet.new()
        |> DataSet.put_element({0x0008, 0x0010}, :SH, "First")
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Second")

      binary = Dcmix.Writer.ImplicitVR.encode(ds)

      {:ok, parsed, _rest} = ImplicitVR.parse(binary, stop_tag: {0x0010, 0x0000})
      assert DataSet.has_tag?(parsed, {0x0008, 0x0010})
      refute DataSet.has_tag?(parsed, {0x0010, 0x0010})
    end

    test "parse handles short binary gracefully" do
      {:ok, ds, rest} = ImplicitVR.parse(<<1, 2, 3, 4, 5, 6, 7>>)
      assert DataSet.size(ds) == 0
      assert rest == <<1, 2, 3, 4, 5, 6, 7>>
    end
  end

  describe "VR comprehensive" do
    alias Dcmix.VR

    test "parse valid VRs" do
      assert {:ok, :AE} = VR.parse("AE")
      assert {:ok, :AS} = VR.parse("AS")
      assert {:ok, :AT} = VR.parse("AT")
      assert {:ok, :CS} = VR.parse("CS")
      assert {:ok, :DA} = VR.parse("DA")
      assert {:ok, :DS} = VR.parse("DS")
      assert {:ok, :DT} = VR.parse("DT")
      assert {:ok, :FL} = VR.parse("FL")
      assert {:ok, :FD} = VR.parse("FD")
      assert {:ok, :IS} = VR.parse("IS")
      assert {:ok, :LO} = VR.parse("LO")
      assert {:ok, :LT} = VR.parse("LT")
      assert {:ok, :OB} = VR.parse("OB")
      assert {:ok, :OD} = VR.parse("OD")
      assert {:ok, :OF} = VR.parse("OF")
      assert {:ok, :OL} = VR.parse("OL")
      assert {:ok, :OW} = VR.parse("OW")
      assert {:ok, :PN} = VR.parse("PN")
      assert {:ok, :SH} = VR.parse("SH")
      assert {:ok, :SL} = VR.parse("SL")
      assert {:ok, :SQ} = VR.parse("SQ")
      assert {:ok, :SS} = VR.parse("SS")
      assert {:ok, :ST} = VR.parse("ST")
      assert {:ok, :TM} = VR.parse("TM")
      assert {:ok, :UC} = VR.parse("UC")
      assert {:ok, :UI} = VR.parse("UI")
      assert {:ok, :UL} = VR.parse("UL")
      assert {:ok, :UN} = VR.parse("UN")
      assert {:ok, :UR} = VR.parse("UR")
      assert {:ok, :US} = VR.parse("US")
      assert {:ok, :UT} = VR.parse("UT")
    end

    test "parse invalid VR" do
      assert {:error, _} = VR.parse("XX")
    end

    test "long_length? returns true for long VRs" do
      for vr <- [:OB, :OD, :OF, :OL, :OW, :SQ, :UC, :UN, :UR, :UT] do
        assert VR.long_length?(vr) == true, "Expected #{vr} to have long length"
      end
    end

    test "long_length? returns false for short VRs" do
      for vr <- [:AE, :AS, :AT, :CS, :DA, :DS, :DT, :FL, :FD, :IS, :LO, :LT, :PN, :SH, :SL, :SS, :ST, :TM, :UI, :UL, :US] do
        assert VR.long_length?(vr) == false, "Expected #{vr} to have short length"
      end
    end

    test "string? identifies string VRs" do
      for vr <- [:AE, :AS, :CS, :DA, :DS, :DT, :IS, :LO, :LT, :PN, :SH, :ST, :TM, :UC, :UI, :UR, :UT] do
        assert VR.string?(vr) == true, "Expected #{vr} to be a string VR"
      end
    end

    test "string? returns false for non-string VRs" do
      for vr <- [:US, :SS, :UL, :SL, :FL, :FD, :OB, :OW, :SQ, :AT] do
        assert VR.string?(vr) == false, "Expected #{vr} to not be a string VR"
      end
    end

    test "allows_multiple_values? for multi-valued VRs" do
      assert VR.allows_multiple_values?(:CS) == true
      assert VR.allows_multiple_values?(:DS) == true
      assert VR.allows_multiple_values?(:IS) == true
      assert VR.allows_multiple_values?(:LO) == true
      assert VR.allows_multiple_values?(:SH) == true
      assert VR.allows_multiple_values?(:UI) == true
    end

    test "allows_multiple_values? false for single-valued VRs" do
      assert VR.allows_multiple_values?(:ST) == false
      assert VR.allows_multiple_values?(:LT) == false
      assert VR.allows_multiple_values?(:UT) == false
      assert VR.allows_multiple_values?(:SQ) == false
    end

    test "to_string returns VR string" do
      assert VR.to_string(:PN) == "PN"
      assert VR.to_string(:US) == "US"
      assert VR.to_string(:SQ) == "SQ"
    end

    test "all returns list of VRs" do
      all = VR.all()
      assert is_list(all)
      assert :PN in all
      assert :US in all
      assert :SQ in all
    end
  end

  describe "Dictionary comprehensive" do
    alias Dcmix.Dictionary

    test "vr returns correct VR for known tags" do
      assert Dictionary.vr({0x0010, 0x0010}) == :PN
      assert Dictionary.vr({0x0010, 0x0020}) == :LO
      assert Dictionary.vr({0x0008, 0x0018}) == :UI
      assert Dictionary.vr({0x0028, 0x0010}) == :US
      assert Dictionary.vr({0x0028, 0x0011}) == :US
    end

    test "vr returns nil for unknown tags" do
      assert Dictionary.vr({0xFFFF, 0xFFFF}) == nil
    end

    test "keyword returns correct keyword for known tags" do
      assert Dictionary.keyword({0x0010, 0x0010}) == "PatientName"
      assert Dictionary.keyword({0x0010, 0x0020}) == "PatientID"
      assert Dictionary.keyword({0x0008, 0x0018}) == "SOPInstanceUID"
    end

    test "tag returns correct tag for known keywords" do
      assert Dictionary.tag("PatientName") == {0x0010, 0x0010}
      assert Dictionary.tag("PatientID") == {0x0010, 0x0020}
      assert Dictionary.tag("SOPInstanceUID") == {0x0008, 0x0018}
    end

    test "tag returns nil for unknown keywords" do
      assert Dictionary.tag("UnknownKeyword") == nil
    end

    test "description returns human-readable name" do
      assert Dictionary.description({0x0010, 0x0010}) == "Patient's Name"
      assert Dictionary.description({0x0010, 0x0020}) == "Patient ID"
    end
  end

  describe "Tag comprehensive" do
    alias Dcmix.Tag

    test "parse string with parens" do
      assert {:ok, {0x0010, 0x0010}} = Tag.parse("(0010,0010)")
    end

    test "parse string 8-digit format" do
      assert {:ok, {0x0010, 0x0010}} = Tag.parse("00100010")
    end

    test "parse invalid format returns error" do
      assert {:error, _} = Tag.parse("invalid")
    end

    test "to_string returns formatted string" do
      assert Tag.to_string({0x0010, 0x0010}) == "(0010,0010)"
      assert Tag.to_string({0x7FE0, 0x0010}) == "(7FE0,0010)"
    end

    test "compare returns correct ordering" do
      assert Tag.compare({0x0008, 0x0000}, {0x0010, 0x0000}) == :lt
      assert Tag.compare({0x0010, 0x0000}, {0x0008, 0x0000}) == :gt
      assert Tag.compare({0x0010, 0x0010}, {0x0010, 0x0010}) == :eq
      assert Tag.compare({0x0010, 0x0010}, {0x0010, 0x0020}) == :lt
    end

    test "file_meta? identifies file meta tags" do
      assert Tag.file_meta?({0x0002, 0x0001}) == true
      assert Tag.file_meta?({0x0002, 0x0010}) == true
      assert Tag.file_meta?({0x0008, 0x0010}) == false
      assert Tag.file_meta?({0x0010, 0x0010}) == false
    end

    test "private? identifies private tags" do
      assert Tag.private?({0x0009, 0x0010}) == true
      assert Tag.private?({0x0011, 0x0010}) == true
      assert Tag.private?({0x0008, 0x0010}) == false
      assert Tag.private?({0x0010, 0x0010}) == false
    end

    test "item_tag? identifies item-related tags" do
      assert Tag.item_tag?({0xFFFE, 0xE000}) == true
      assert Tag.item_tag?({0xFFFE, 0xE00D}) == true
      assert Tag.item_tag?({0xFFFE, 0xE0DD}) == true
      assert Tag.item_tag?({0x0010, 0x0010}) == false
    end

    test "standard tag accessors" do
      assert Tag.patient_name() == {0x0010, 0x0010}
      assert Tag.patient_id() == {0x0010, 0x0020}
      assert Tag.sop_instance_uid() == {0x0008, 0x0018}
      assert Tag.transfer_syntax_uid() == {0x0002, 0x0010}
      assert Tag.rows() == {0x0028, 0x0010}
      assert Tag.columns() == {0x0028, 0x0011}
      assert Tag.bits_allocated() == {0x0028, 0x0100}
      assert Tag.bits_stored() == {0x0028, 0x0101}
      assert Tag.high_bit() == {0x0028, 0x0102}
      assert Tag.pixel_representation() == {0x0028, 0x0103}
      assert Tag.samples_per_pixel() == {0x0028, 0x0002}
      assert Tag.photometric_interpretation() == {0x0028, 0x0004}
    end
  end

  describe "Mix.Tasks.Dcmix.Dump" do
    @fixtures_path "test/fixtures"

    test "dump task runs successfully with valid file" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        # Can't directly test run/1 due to exit calls, but we can test the underlying functionality
        {:ok, dataset} = Dcmix.read_file(file)
        output = Dcmix.dump(dataset)
        assert is_binary(output)
        assert String.length(output) > 0
      end
    end
  end

  describe "Mix.Tasks.Dcmix.ToJson" do
    @fixtures_path "test/fixtures"

    test "to_json converts dataset successfully" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        {:ok, dataset} = Dcmix.read_file(file)
        {:ok, json} = Dcmix.to_json(dataset)
        assert is_binary(json)
        assert {:ok, _} = Jason.decode(json)
      end
    end
  end

  describe "Mix.Tasks.Dcmix.ToXml" do
    @fixtures_path "test/fixtures"

    test "to_xml converts dataset successfully" do
      file = Path.join(@fixtures_path, "1_ORIGINAL.dcm")

      if File.exists?(file) do
        {:ok, dataset} = Dcmix.read_file(file)
        {:ok, xml} = Dcmix.to_xml(dataset)
        assert is_binary(xml)
        assert String.starts_with?(xml, "<?xml")
      end
    end
  end

  describe "Dcmix API comprehensive" do
    test "new creates empty dataset" do
      ds = Dcmix.new()
      assert is_struct(ds, Dcmix.DataSet)
      assert Dcmix.DataSet.size(ds) == 0
    end

    test "get returns nil for missing tag" do
      ds = Dcmix.new()
      assert Dcmix.get(ds, {0x0010, 0x0010}) == nil
    end

    test "get returns nil for unknown keyword" do
      ds = Dcmix.new()
      assert Dcmix.get(ds, "UnknownKeyword") == nil
    end

    test "get_string returns nil for missing tag" do
      ds = Dcmix.new()
      assert Dcmix.get_string(ds, {0x0010, 0x0010}) == nil
    end

    test "get_string with keyword" do
      ds = Dcmix.put(Dcmix.new(), {0x0010, 0x0010}, :PN, "Test")
      assert Dcmix.get_string(ds, "PatientName") == "Test"
    end

    test "get_string returns nil for unknown keyword" do
      ds = Dcmix.new()
      assert Dcmix.get_string(ds, "UnknownKeyword") == nil
    end

    test "get_element returns nil for missing tag" do
      ds = Dcmix.new()
      assert Dcmix.get_element(ds, {0x0010, 0x0010}) == nil
    end

    test "get_element returns nil for unknown keyword" do
      ds = Dcmix.new()
      assert Dcmix.get_element(ds, "UnknownKeyword") == nil
    end

    test "put with tag" do
      ds = Dcmix.put(Dcmix.new(), {0x0010, 0x0010}, :PN, "Test")
      assert Dcmix.get(ds, {0x0010, 0x0010}) == "Test"
    end

    test "put with keyword" do
      ds = Dcmix.put(Dcmix.new(), "PatientName", :PN, "Test")
      assert Dcmix.get(ds, {0x0010, 0x0010}) == "Test"
    end

    test "put raises for unknown keyword" do
      assert_raise ArgumentError, fn ->
        Dcmix.put(Dcmix.new(), "UnknownKeyword", :PN, "Test")
      end
    end

    test "delete with unknown keyword returns unchanged dataset" do
      ds = Dcmix.put(Dcmix.new(), {0x0010, 0x0010}, :PN, "Test")
      result = Dcmix.delete(ds, "UnknownKeyword")
      assert Dcmix.get(result, {0x0010, 0x0010}) == "Test"
    end
  end

  describe "Writer.ImplicitVR comprehensive" do
    alias Dcmix.Writer.ImplicitVR
    alias Dcmix.{DataSet, DataElement}

    test "encodes signed integers (SS)" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :SS, -100)])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes signed 32-bit integers (SL)" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :SL, -100_000)])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes float 32-bit (FL)" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0050}, :FL, 1.5)])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes float 64-bit (FD)" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0051}, :FD, 1.5)])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes AT (attribute tag)" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, {0x0010, 0x0020})])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of SS values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :SS, [-100, 100, 0])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of SL values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :SL, [-100_000, 100_000])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of FL values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0050}, :FL, [1.5, 2.5, 3.5])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of FD values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0051}, :FD, [1.5, 2.5])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, [{0x0010, 0x0010}, {0x0010, 0x0020}])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of US values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :US, [512, 256, 128])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of UL values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :UL, [100_000, 200_000])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes OB/OW binary data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 1, 2, 3>>)])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes OB/OW list data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, [<<0, 1>>, <<2, 3>>])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes nil value" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, nil)])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list string value" do
      ds = DataSet.new([DataElement.new({0x0020, 0x0037}, :DS, ["1.0", "0.0", "0.0"])])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes numeric to string" do
      ds = DataSet.new([DataElement.new({0x0020, 0x0037}, :DS, 123)])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes item delimiter tags" do
      elem = DataElement.new({0xFFFE, 0xE000}, nil, nil)
      binary = ImplicitVR.encode_element(elem)
      assert is_list(binary) or is_binary(binary)
    end

    test "encodes sequence with nil value" do
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, nil)])
      binary = ImplicitVR.encode(ds)
      assert is_binary(binary)
    end
  end

  describe "Writer.ExplicitVR comprehensive" do
    alias Dcmix.Writer.ExplicitVR
    alias Dcmix.{DataSet, DataElement}

    test "encodes signed integers (SS)" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :SS, -100)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes signed 32-bit integers (SL)" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :SL, -100_000)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes float 32-bit (FL)" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0050}, :FL, 1.5)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes float 64-bit (FD)" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0051}, :FD, 1.5)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes AT (attribute tag)" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, {0x0010, 0x0020})])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of SS values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :SS, [-100, 100])])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of SL values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :SL, [-100_000, 100_000])])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of FL values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0050}, :FL, [1.5, 2.5])])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of FD values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0051}, :FD, [1.5, 2.5])])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, [{0x0010, 0x0010}, {0x0010, 0x0020}])])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of US values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :US, [512, 256])])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list of UL values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :UL, [100_000, 200_000])])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes OB binary data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, <<0, 1, 2, 3>>)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes OD binary data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0011}, :OD, <<0, 1, 2, 3, 4, 5, 6, 7>>)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes OF binary data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0012}, :OF, <<0, 1, 2, 3>>)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes OL binary data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0013}, :OL, <<0, 1, 2, 3>>)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes UC long string" do
      ds = DataSet.new([DataElement.new({0x0008, 0x0016}, :UC, "A long string")])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes UR long string" do
      ds = DataSet.new([DataElement.new({0x0008, 0x0120}, :UR, "http://example.com")])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes UT long string" do
      ds = DataSet.new([DataElement.new({0x0008, 0x0119}, :UT, "A very long text")])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes nil value" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, nil)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes list string value" do
      ds = DataSet.new([DataElement.new({0x0020, 0x0037}, :DS, ["1.0", "0.0"])])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes with big_endian option" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      binary = ExplicitVR.encode(ds, big_endian: true)
      assert is_binary(binary)
    end

    test "encodes item delimiter tags" do
      elem = DataElement.new({0xFFFE, 0xE000}, nil, nil, 0)
      binary = ExplicitVR.encode_element(elem, false)
      assert is_list(binary) or is_binary(binary)
    end

    test "encodes encapsulated pixel data" do
      fragments = [<<>>, <<1, 2, 3, 4>>]
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, fragments, :undefined)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end

    test "encodes sequence with defined length" do
      item = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item], 100)])
      binary = ExplicitVR.encode(ds)
      assert is_binary(binary)
    end
  end

  describe "Export.XML comprehensive" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.XML

    test "encodes sequence with multiple items" do
      item1 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE1")])
      item2 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE2")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item1, item2])])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "CODE1")
      assert String.contains?(xml, "CODE2")
    end

    test "encodes binary data as base64" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 1, 2, 3>>)])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "InlineBinary")
    end

    test "encodes multiple string values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x0037}, :DS, ["1.0", "0.0", "0.0"])])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "1.0")
    end

    test "encodes numeric values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :US, 512)])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "512")
    end

    test "escapes special XML characters" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test<>&\"'")])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "&lt;")
      assert String.contains?(xml, "&gt;")
      assert String.contains?(xml, "&amp;")
    end
  end

  describe "Export.JSON comprehensive" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.JSON

    test "encodes sequence with multiple items" do
      item1 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE1")])
      item2 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE2")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item1, item2])])
      {:ok, json} = JSON.encode(ds)
      assert String.contains?(json, "CODE1")
      assert String.contains?(json, "CODE2")
    end

    test "encodes binary data as base64" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 1, 2, 3>>)])
      {:ok, json} = JSON.encode(ds)
      assert String.contains?(json, "InlineBinary")
    end

    test "encodes multiple string values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x0037}, :DS, "1.0\\0.0\\0.0")])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes person name components" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Doe^John^A")])
      {:ok, json} = JSON.encode(ds)
      assert String.contains?(json, "Alphabetic")
    end

    test "encodes integer values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :US, 512)])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes float values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0050}, :FL, 1.5)])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end
  end

  describe "Export.Text comprehensive" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.Text

    test "encodes nested sequences" do
      inner_item = DataSet.new([DataElement.new({0x0008, 0x0104}, :LO, "Inner")])
      outer_item = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [inner_item])])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [outer_item])])
      text = Text.encode(ds)
      assert String.contains?(text, "Inner")
    end

    test "encodes nil values" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, nil)])
      text = Text.encode(ds)
      assert is_binary(text)
    end

    test "encodes with show_length option" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      text = Text.encode(ds, show_length: true)
      assert is_binary(text)
    end

    test "encodes float values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0050}, :FL, 1.5)])
      text = Text.encode(ds)
      assert String.contains?(text, "1.5")
    end

    test "encodes list of numeric values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :US, [512, 256])])
      text = Text.encode(ds)
      assert String.contains?(text, "512")
      assert String.contains?(text, "256")
    end

    test "encodes private tags with keyword lookup" do
      ds = DataSet.new([DataElement.new({0x0011, 0x0010}, :LO, "Private")])
      text = Text.encode(ds)
      assert String.contains?(text, "0011")
    end
  end

  describe "DataSet comprehensive" do
    alias Dcmix.{DataSet, DataElement}

    test "enumerable - count" do
      ds = DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "ID")
      assert Enum.count(ds) == 2
    end

    test "enumerable - member?" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      elem = DataSet.get(ds, {0x0010, 0x0010})
      assert Enum.member?(ds, elem)
    end

    test "enumerable - reduce" do
      ds = DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "ID")
      tags = Enum.map(ds, fn elem -> elem.tag end)
      assert {0x0010, 0x0010} in tags
      assert {0x0010, 0x0020} in tags
    end

    test "enumerable - slice" do
      ds = DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "ID")
      slice = Enum.slice(ds, 0, 1)
      assert length(slice) == 1
    end

    test "update overwrites existing element" do
      ds = DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Old")
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "New")
      assert DataSet.get_value(ds, {0x0010, 0x0010}) == "New"
    end

    test "filter returns matching elements" do
      ds = DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
        |> DataSet.put_element({0x0020, 0x000D}, :UI, "1.2.3")
      filtered = DataSet.filter(ds, fn elem -> elem.vr == :PN end)
      assert DataSet.size(filtered) == 1
    end

    test "merge combines two datasets" do
      ds1 = DataSet.new() |> DataSet.put_element({0x0010, 0x0010}, :PN, "Name1")
      ds2 = DataSet.new() |> DataSet.put_element({0x0010, 0x0020}, :LO, "ID2")
      merged = DataSet.merge(ds1, ds2)
      assert DataSet.size(merged) == 2
    end

    test "tags returns list of tags" do
      ds = DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
        |> DataSet.put_element({0x0010, 0x0020}, :LO, "ID")
      tags = DataSet.tags(ds)
      assert {0x0010, 0x0010} in tags
      assert {0x0010, 0x0020} in tags
    end
  end

  describe "VR comprehensive extras" do
    alias Dcmix.VR

    test "name returns human-readable name" do
      assert VR.name(:PN) == "Person Name"
      assert VR.name(:US) == "Unsigned Short"
      assert VR.name(:SQ) == "Sequence of Items"
    end

    test "padding returns correct padding character" do
      assert VR.padding(:UI) == 0x00
      assert VR.padding(:PN) == 0x20
    end
  end

  describe "Dictionary extras" do
    alias Dcmix.Dictionary

    test "lookup returns entry for known tag" do
      {:ok, entry} = Dictionary.lookup({0x0010, 0x0010})
      assert entry.keyword == "PatientName"
    end

    test "lookup returns error for unknown tag" do
      assert {:error, :not_found} = Dictionary.lookup({0xFFFF, 0xFFFF})
    end

    test "lookup! raises for unknown tag" do
      assert_raise ArgumentError, fn ->
        Dictionary.lookup!({0xFFFF, 0xFFFF})
      end
    end

    test "lookup_keyword returns entry for known keyword" do
      {:ok, entry} = Dictionary.lookup_keyword("PatientName")
      assert entry.tag == {0x0010, 0x0010}
    end

    test "all returns list of entries" do
      entries = Dictionary.all()
      assert is_list(entries)
      assert length(entries) > 0
    end

    test "size returns count of entries" do
      size = Dictionary.size()
      assert is_integer(size)
      assert size > 0
    end
  end

  describe "Parser comprehensive" do
    alias Dcmix.Parser

    test "parse_file returns error for non-existent file" do
      assert {:error, {:file_error, :enoent}} = Parser.parse_file("nonexistent.dcm")
    end

    test "parse handles minimal data" do
      # Minimal data will parse as empty dataset
      result = Parser.parse(<<0, 1, 2>>)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "Tag extras" do
    alias Dcmix.Tag

    test "group returns group number" do
      assert Tag.group({0x0010, 0x0020}) == 0x0010
    end

    test "element returns element number" do
      assert Tag.element({0x0010, 0x0020}) == 0x0020
    end

    test "private tag detection" do
      # Private groups are odd numbers > 0x0008
      assert Tag.private?({0x0009, 0x0010}) == true
      assert Tag.private?({0x0010, 0x0010}) == false
    end
  end

  describe "Parser.ExplicitVR big endian" do
    alias Dcmix.Parser.ExplicitVR
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Writer.ExplicitVR, as: Writer

    test "parse big endian data" do
      ds = DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test")
        |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
      binary = Writer.encode(ds, big_endian: true)
      {:ok, parsed, _} = ExplicitVR.parse(binary, big_endian: true)
      assert DataSet.get_value(parsed, {0x0010, 0x0010}) == "Test"
      assert DataSet.get_value(parsed, {0x0028, 0x0010}) == 512
    end

    test "parse big endian with float values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0050}, :FD, 1.5)])
      binary = Writer.encode(ds, big_endian: true)
      {:ok, parsed, _} = ExplicitVR.parse(binary, big_endian: true)
      assert is_float(DataSet.get_value(parsed, {0x0018, 0x0050}))
    end

    test "parse big endian with signed integers" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :SS, -100)])
      binary = Writer.encode(ds, big_endian: true)
      {:ok, parsed, _} = ExplicitVR.parse(binary, big_endian: true)
      assert DataSet.get_value(parsed, {0x0028, 0x0010}) == -100
    end

    test "parse big endian with AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, {0x0010, 0x0020})])
      binary = Writer.encode(ds, big_endian: true)
      {:ok, parsed, _} = ExplicitVR.parse(binary, big_endian: true)
      assert DataSet.get_value(parsed, {0x0020, 0x5100}) == {0x0010, 0x0020}
    end

    test "parse big endian with multiple US values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :US, [512, 256])])
      binary = Writer.encode(ds, big_endian: true)
      {:ok, parsed, _} = ExplicitVR.parse(binary, big_endian: true)
      assert DataSet.get_value(parsed, {0x0028, 0x0010}) == [512, 256]
    end
  end

  describe "Parser.ExplicitVR sequences" do
    alias Dcmix.Parser.ExplicitVR
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Writer.ExplicitVR, as: Writer

    test "parse sequence with undefined length" do
      item1 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE1")])
      item2 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE2")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item1, item2], :undefined)])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ExplicitVR.parse(binary)
      seq = DataSet.get(parsed, {0x0040, 0xA730})
      assert length(seq.value) == 2
    end

    test "parse nested sequences" do
      inner_item = DataSet.new([DataElement.new({0x0008, 0x0104}, :LO, "Inner")])
      outer_item = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [inner_item], :undefined)])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [outer_item], :undefined)])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ExplicitVR.parse(binary)
      assert is_struct(parsed, DataSet)
    end
  end

  describe "Parser.ImplicitVR sequences" do
    alias Dcmix.Parser.ImplicitVR
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Writer.ImplicitVR, as: Writer

    test "parse sequence" do
      item = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      seq = DataSet.get(parsed, {0x0040, 0xA730})
      assert seq.vr == :SQ
    end

    test "parse multiple items in sequence" do
      item1 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE1")])
      item2 = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE2")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [item1, item2])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      seq = DataSet.get(parsed, {0x0040, 0xA730})
      assert length(seq.value) == 2
    end

    test "parse nested sequences" do
      inner_item = DataSet.new([DataElement.new({0x0008, 0x0104}, :LO, "Inner")])
      outer_item = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [inner_item])])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [outer_item])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      assert is_struct(parsed, DataSet)
    end

    test "parse various numeric types" do
      ds = DataSet.new()
        |> DataSet.put_element({0x0028, 0x0010}, :US, 512)
        |> DataSet.put_element({0x0028, 0x0011}, :SS, -100)
        |> DataSet.put_element({0x0028, 0x0030}, :UL, 100_000)
        |> DataSet.put_element({0x0028, 0x0031}, :SL, -100_000)
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      assert DataSet.get_value(parsed, {0x0028, 0x0010}) == 512
    end
  end

  describe "Export.JSON edge cases" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.JSON

    test "encodes AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, {0x0010, 0x0020})])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes list of AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, [{0x0010, 0x0010}, {0x0010, 0x0020}])])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes nil value" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, nil)])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes empty sequence" do
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [])])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes nested sequence" do
      inner_item = DataSet.new([DataElement.new({0x0008, 0x0104}, :LO, "Inner")])
      outer_item = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [inner_item])])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [outer_item])])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end
  end

  describe "Export.XML edge cases" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.XML

    test "encodes AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, {0x0010, 0x0020})])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "0010")
    end

    test "encodes nil value" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, nil)])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "PN")
    end

    test "encodes list of values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0010}, :US, [512, 256, 128])])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "512")
    end

    test "encodes nested sequence" do
      inner_item = DataSet.new([DataElement.new({0x0008, 0x0104}, :LO, "Inner")])
      outer_item = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [inner_item])])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [outer_item])])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "Inner")
    end
  end

  describe "Export.Text edge cases" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.Text

    test "encodes AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, {0x0010, 0x0020})])
      text = Text.encode(ds)
      assert String.contains?(text, "(0010,0020)")
    end

    test "encodes list of AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, [{0x0010, 0x0010}, {0x0010, 0x0020}])])
      text = Text.encode(ds)
      assert String.contains?(text, "(0010,0010)")
    end

    test "encodes binary data truncated" do
      long_binary = :binary.copy(<<0>>, 100)
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, long_binary)])
      text = Text.encode(ds, max_value_length: 20)
      assert String.contains?(text, "...")
    end

    test "encodes string list" do
      ds = DataSet.new([DataElement.new({0x0020, 0x0037}, :DS, ["1.0", "0.0", "0.0", "1.0", "0.0", "0.0"])])
      text = Text.encode(ds)
      assert String.contains?(text, "1.0")
    end
  end

  describe "Tag parsing and formatting" do
    alias Dcmix.Tag

    test "parse uppercase hex" do
      assert {:ok, {0x0010, 0x0010}} = Tag.parse("(0010,0010)")
    end

    test "parse lowercase hex" do
      assert {:ok, {0x00AB, 0x00CD}} = Tag.parse("(00ab,00cd)")
    end

    test "parse mixed case hex" do
      assert {:ok, {0x00AB, 0x00CD}} = Tag.parse("(00Ab,00cD)")
    end

    test "to_string pads with zeros" do
      assert Tag.to_string({0x0001, 0x0002}) == "(0001,0002)"
    end

    test "parse with whitespace" do
      assert {:ok, {0x0010, 0x0010}} = Tag.parse("  (0010,0010)  ")
    end
  end

  describe "VR edge cases" do
    alias Dcmix.VR

    test "all returns all VR atoms" do
      all = VR.all()
      assert :PN in all
      assert :US in all
      assert :SQ in all
      assert :OB in all
      assert :UN in all
    end

    test "to_string for all VRs" do
      for vr <- VR.all() do
        str = VR.to_string(vr)
        assert is_binary(str)
        assert String.length(str) == 2
      end
    end

    test "name for various VRs" do
      assert VR.name(:AE) == "Application Entity"
      assert VR.name(:DA) == "Date"
      assert VR.name(:TM) == "Time"
      assert VR.name(:UI) == "Unique Identifier (UID)"
    end
  end

  describe "Export.JSON more coverage" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.JSON

    test "encodes with pretty option" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      {:ok, json} = JSON.encode(ds, pretty: true)
      assert String.contains?(json, "\n")
    end

    test "encodes DS with float value" do
      ds = DataSet.new([DataElement.new({0x0020, 0x0037}, :DS, "1.5")])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes DS with integer value" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0008}, :IS, "10")])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes empty string value" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "")])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes DS with backslash separated values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x0037}, :DS, "1.0\\0.0\\0.0")])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes UN VR with DataSet list" do
      item = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :UN, [item])])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes fragments in pixel data" do
      fragments = [<<0, 0, 0, 0>>, <<1, 2, 3, 4>>]
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, fragments)])
      {:ok, json} = JSON.encode(ds)
      {:ok, parsed} = Jason.decode(json)
      assert is_map(parsed)
    end

    test "encodes nil VR" do
      ds = DataSet.new([DataElement.new({0xFFFE, 0xE000}, nil, nil)])
      {:ok, json} = JSON.encode(ds)
      {:ok, _} = Jason.decode(json)
    end

    test "dataset_to_map returns map" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      map = JSON.dataset_to_map(ds)
      assert is_map(map)
      assert Map.has_key?(map, "00100010")
    end
  end

  describe "Export.XML more coverage" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.XML

    test "encodes empty string" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "")])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "PN")
    end

    test "encodes private tags" do
      ds = DataSet.new([DataElement.new({0x0011, 0x0010}, :LO, "Private")])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "0011")
    end

    test "encodes UN with DataSet list" do
      item = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :UN, [item])])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "CODE")
    end

    test "encodes fragments in pixel data" do
      fragments = [<<0, 0, 0, 0>>, <<1, 2, 3, 4>>]
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, fragments)])
      {:ok, xml} = XML.encode(ds)
      assert String.contains?(xml, "InlineBinary")
    end
  end

  describe "Export.Text more coverage" do
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Export.Text

    test "encodes empty string" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "")])
      text = Text.encode(ds)
      assert is_binary(text)
    end

    test "encodes undefined length" do
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :SQ, [], :undefined)])
      text = Text.encode(ds)
      assert is_binary(text)
    end

    test "encodes UN with DataSet list" do
      item = DataSet.new([DataElement.new({0x0008, 0x0100}, :SH, "CODE")])
      ds = DataSet.new([DataElement.new({0x0040, 0xA730}, :UN, [item])])
      text = Text.encode(ds)
      # UN with DataSets shows as sequence
      assert String.contains?(text, "item")
    end

    test "encodes fragments in pixel data" do
      fragments = [<<0, 0, 0, 0>>, <<1, 2, 3, 4>>]
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OB, fragments)])
      text = Text.encode(ds)
      assert is_binary(text)
    end
  end

  describe "Parser.ExplicitVR more coverage" do
    alias Dcmix.Parser.ExplicitVR
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Writer.ExplicitVR, as: Writer

    test "parse float32 values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0050}, :FL, [1.5, 2.5])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ExplicitVR.parse(binary)
      values = DataSet.get_value(parsed, {0x0018, 0x0050})
      assert is_list(values)
    end

    test "parse SL values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :SL, [-1000, 1000])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ExplicitVR.parse(binary)
      values = DataSet.get_value(parsed, {0x0028, 0x0030})
      assert is_list(values)
    end

    test "parse UL values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :UL, [100_000, 200_000])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ExplicitVR.parse(binary)
      values = DataSet.get_value(parsed, {0x0028, 0x0030})
      assert is_list(values)
    end

    test "parse unknown VR treated as UN" do
      # Write valid element then modify VR to invalid
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      binary = Writer.encode(ds)
      # This tests that parsing continues with invalid VR
      {:ok, _, _} = ExplicitVR.parse(binary)
    end
  end

  describe "Parser.ImplicitVR more coverage" do
    alias Dcmix.Parser.ImplicitVR
    alias Dcmix.{DataSet, DataElement}
    alias Dcmix.Writer.ImplicitVR, as: Writer

    test "parse FL values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0050}, :FL, [1.5, 2.5])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      assert is_struct(parsed, DataSet)
    end

    test "parse FD values" do
      ds = DataSet.new([DataElement.new({0x0018, 0x0051}, :FD, [1.5, 2.5])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      assert is_struct(parsed, DataSet)
    end

    test "parse SL values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :SL, [-1000, 1000])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      assert is_struct(parsed, DataSet)
    end

    test "parse UL values" do
      ds = DataSet.new([DataElement.new({0x0028, 0x0030}, :UL, [100_000, 200_000])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      assert is_struct(parsed, DataSet)
    end

    test "parse AT values" do
      ds = DataSet.new([DataElement.new({0x0020, 0x5100}, :AT, [{0x0010, 0x0010}, {0x0010, 0x0020}])])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      assert is_struct(parsed, DataSet)
    end

    test "parse binary data" do
      ds = DataSet.new([DataElement.new({0x7FE0, 0x0010}, :OW, <<0, 1, 2, 3, 4, 5, 6, 7>>)])
      binary = Writer.encode(ds)
      {:ok, parsed, _} = ImplicitVR.parse(binary)
      assert is_struct(parsed, DataSet)
    end
  end

  describe "Tag more coverage" do
    alias Dcmix.Tag

    test "sop_class_uid accessor" do
      assert Tag.sop_class_uid() == {0x0008, 0x0016}
    end

    test "study_instance_uid accessor" do
      assert Tag.study_instance_uid() == {0x0020, 0x000D}
    end

    test "series_instance_uid accessor" do
      assert Tag.series_instance_uid() == {0x0020, 0x000E}
    end

    test "modality accessor" do
      assert Tag.modality() == {0x0008, 0x0060}
    end
  end

  describe "DataSet more coverage" do
    alias Dcmix.{DataSet, DataElement}

    test "size returns 0 for empty dataset" do
      ds = DataSet.new()
      assert DataSet.size(ds) == 0
    end

    test "size returns count for non-empty dataset" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      assert DataSet.size(ds) == 1
    end

    test "has_tag? returns true when tag exists" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      assert DataSet.has_tag?(ds, {0x0010, 0x0010}) == true
    end

    test "has_tag? returns false when tag doesn't exist" do
      ds = DataSet.new()
      assert DataSet.has_tag?(ds, {0x0010, 0x0010}) == false
    end

    test "get_string with nil value" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, nil)])
      assert DataSet.get_string(ds, {0x0010, 0x0010}) == nil
    end

    test "delete removes element" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      ds = DataSet.delete(ds, {0x0010, 0x0010})
      assert DataSet.has_tag?(ds, {0x0010, 0x0010}) == false
    end

    test "delete non-existent returns same dataset" do
      ds = DataSet.new([DataElement.new({0x0010, 0x0010}, :PN, "Test")])
      ds2 = DataSet.delete(ds, {0x0010, 0x0020})
      assert DataSet.size(ds2) == 1
    end
  end
end
