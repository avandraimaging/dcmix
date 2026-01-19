defmodule Dcmix.Import.XMLTest do
  use ExUnit.Case, async: true

  alias Dcmix.Import.XML
  alias Dcmix.DataSet

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "0_ORIGINAL.dcm")

  describe "decode/2" do
    test "decodes simple DICOM XML" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel xmlns="http://dicom.nema.org/PS3.19/models/NativeDICOM">
        <DicomAttribute tag="00100010" vr="PN" keyword="PatientName">
          <PersonName number="1"><Alphabetic><FamilyName>Doe</FamilyName><GivenName>John</GivenName></Alphabetic></PersonName>
        </DicomAttribute>
        <DicomAttribute tag="00100020" vr="LO" keyword="PatientID">
          <Value number="1">12345</Value>
        </DicomAttribute>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml)
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "Doe^John"
      assert DataSet.get_string(dataset, {0x0010, 0x0020}) == "12345"
    end

    test "decodes numeric values" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00280010" vr="US" keyword="Rows">
          <Value number="1">512</Value>
        </DicomAttribute>
        <DicomAttribute tag="00280011" vr="US" keyword="Columns">
          <Value number="1">512</Value>
        </DicomAttribute>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml)
      assert DataSet.get_value(dataset, {0x0028, 0x0010}) == 512
      assert DataSet.get_value(dataset, {0x0028, 0x0011}) == 512
    end

    test "decodes multiple values" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00080008" vr="CS" keyword="ImageType">
          <Value number="1">ORIGINAL</Value>
          <Value number="2">PRIMARY</Value>
        </DicomAttribute>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml)
      assert DataSet.get_string(dataset, {0x0008, 0x0008}) == "ORIGINAL\\PRIMARY"
    end

    test "decodes InlineBinary" do
      base64_data = Base.encode64(<<1, 2, 3, 4>>)

      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="7FE00010" vr="OW" keyword="PixelData">
          <InlineBinary>#{base64_data}</InlineBinary>
        </DicomAttribute>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml)
      assert DataSet.get_value(dataset, {0x7FE0, 0x0010}) == <<1, 2, 3, 4>>
    end

    test "decodes sequences" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00081115" vr="SQ" keyword="ReferencedSeriesSequence">
          <Item number="1">
            <DicomAttribute tag="00081150" vr="UI" keyword="ReferencedSOPClassUID">
              <Value number="1">1.2.3</Value>
            </DicomAttribute>
          </Item>
          <Item number="2">
            <DicomAttribute tag="00081150" vr="UI" keyword="ReferencedSOPClassUID">
              <Value number="1">4.5.6</Value>
            </DicomAttribute>
          </Item>
        </DicomAttribute>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml)
      element = DataSet.get(dataset, {0x0008, 0x1115})
      assert element.vr == :SQ
      assert length(element.value) == 2
    end

    test "decodes float values" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00280030" vr="DS" keyword="PixelSpacing">
          <Value number="1">0.5</Value>
          <Value number="2">0.5</Value>
        </DicomAttribute>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml)
      # DS values are stored as strings
      assert DataSet.get_string(dataset, {0x0028, 0x0030}) == "0.5\\0.5"
    end

    test "decodes empty elements" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00100010" vr="PN" keyword="PatientName"/>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml)
      assert DataSet.get_value(dataset, {0x0010, 0x0010}) == nil
    end

    test "handles XML entities" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00081030" vr="LO" keyword="StudyDescription">
          <Value number="1">Test &amp; Study &lt;1&gt;</Value>
        </DicomAttribute>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml)
      assert DataSet.get_string(dataset, {0x0008, 0x1030}) == "Test & Study <1>"
    end

    test "merges with template dataset" do
      template =
        DataSet.new()
        |> DataSet.put_element({0x0010, 0x0010}, :PN, "Template^Name")
        |> DataSet.put_element({0x0010, 0x0030}, :DA, "19800101")

      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00100010" vr="PN" keyword="PatientName">
          <PersonName number="1"><Alphabetic><FamilyName>New</FamilyName><GivenName>Name</GivenName></Alphabetic></PersonName>
        </DicomAttribute>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml, template: template)
      # Name should be overwritten
      assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "New^Name"
      # Birth date should be preserved from template
      assert DataSet.get_string(dataset, {0x0010, 0x0030}) == "19800101"
    end

    test "handles AT values" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00209165" vr="AT" keyword="DimensionIndexPointer">
          <Value number="1">00100010</Value>
        </DicomAttribute>
      </NativeDicomModel>
      """

      assert {:ok, dataset} = XML.decode(xml)
      assert DataSet.get_value(dataset, {0x0020, 0x9165}) == {0x0010, 0x0010}
    end
  end

  describe "decode_file/2" do
    test "decodes XML file" do
      tmp_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(100_000)}.xml")

      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00100010" vr="PN" keyword="PatientName">
          <PersonName number="1"><Alphabetic><FamilyName>Test</FamilyName><GivenName>Patient</GivenName></Alphabetic></PersonName>
        </DicomAttribute>
      </NativeDicomModel>
      """

      File.write!(tmp_file, xml)

      try do
        assert {:ok, dataset} = XML.decode_file(tmp_file)
        assert DataSet.get_string(dataset, {0x0010, 0x0010}) == "Test^Patient"
      after
        File.rm(tmp_file)
      end
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_read_error, :enoent}} = XML.decode_file("nonexistent.xml")
    end
  end

  describe "roundtrip" do
    test "XML export and import roundtrip preserves data" do
      {:ok, original} = Dcmix.read_file(@valid_dcm)

      # Export to XML
      {:ok, xml} = Dcmix.to_xml(original)

      # Import from XML
      {:ok, reimported} = XML.decode(xml)

      # Key attributes should match
      assert DataSet.get_string(reimported, {0x0010, 0x0010}) ==
               DataSet.get_string(original, {0x0010, 0x0010})

      assert DataSet.get_string(reimported, {0x0010, 0x0020}) ==
               DataSet.get_string(original, {0x0010, 0x0020})
    end
  end
end
