defmodule Mix.Tasks.Dcmix.FromXmlTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Dcmix.FromXml

  @fixtures_path "test/fixtures"
  @valid_dcm Path.join(@fixtures_path, "nema_mr_brain_512x512.dcm")

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp create_test_xml do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <NativeDicomModel xmlns="http://dicom.nema.org/PS3.19/models/NativeDICOM">
      <DicomAttribute tag="00100010" vr="PN" keyword="PatientName">
        <PersonName number="1">
          <Alphabetic>
            <FamilyName>Test</FamilyName>
            <GivenName>Patient</GivenName>
          </Alphabetic>
        </PersonName>
      </DicomAttribute>
      <DicomAttribute tag="00100020" vr="LO" keyword="PatientID">
        <Value number="1">TESTID123</Value>
      </DicomAttribute>
      <DicomAttribute tag="00080060" vr="CS" keyword="Modality">
        <Value number="1">CT</Value>
      </DicomAttribute>
    </NativeDicomModel>
    """
  end

  describe "run/1" do
    test "converts XML to DICOM file" do
      tmp_xml = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.xml")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      File.write!(tmp_xml, create_test_xml())

      try do
        FromXml.run([tmp_xml, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"
        assert message =~ tmp_dcm

        assert File.exists?(tmp_dcm)

        # Verify the output is valid DICOM
        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        assert Dcmix.DataSet.get_string(dataset, {0x0010, 0x0010}) == "Test^Patient"
        assert Dcmix.DataSet.get_string(dataset, {0x0010, 0x0020}) == "TESTID123"
      after
        File.rm(tmp_xml)
        File.rm(tmp_dcm)
      end
    end

    test "converts XML with template DICOM" do
      tmp_xml = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.xml")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      # XML that only updates patient name
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00100010" vr="PN" keyword="PatientName">
          <PersonName number="1">
            <Alphabetic>
              <FamilyName>New</FamilyName>
              <GivenName>Name</GivenName>
            </Alphabetic>
          </PersonName>
        </DicomAttribute>
      </NativeDicomModel>
      """

      File.write!(tmp_xml, xml)

      try do
        FromXml.run(["--template", @valid_dcm, tmp_xml, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        # Verify the output has merged data
        {:ok, original} = Dcmix.read_file(@valid_dcm)
        {:ok, dataset} = Dcmix.read_file(tmp_dcm)

        # Name should be from XML
        assert Dcmix.DataSet.get_string(dataset, {0x0010, 0x0010}) == "New^Name"

        # Study UID should be from template
        assert Dcmix.DataSet.get_string(dataset, {0x0020, 0x000D}) ==
                 Dcmix.DataSet.get_string(original, {0x0020, 0x000D})
      after
        File.rm(tmp_xml)
        File.rm(tmp_dcm)
      end
    end

    test "supports -t alias for --template" do
      tmp_xml = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.xml")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <NativeDicomModel>
        <DicomAttribute tag="00100010" vr="PN" keyword="PatientName">
          <PersonName number="1">
            <Alphabetic>
              <FamilyName>Alias</FamilyName>
              <GivenName>Test</GivenName>
            </Alphabetic>
          </PersonName>
        </DicomAttribute>
      </NativeDicomModel>
      """

      File.write!(tmp_xml, xml)

      try do
        FromXml.run(["-t", @valid_dcm, tmp_xml, tmp_dcm])

        assert_received {:mix_shell, :info, [message]}
        assert message =~ "Written to"

        {:ok, dataset} = Dcmix.read_file(tmp_dcm)
        assert Dcmix.DataSet.get_string(dataset, {0x0010, 0x0010}) == "Alias^Test"
      after
        File.rm(tmp_xml)
        File.rm(tmp_dcm)
      end
    end

    test "shows error when no files provided" do
      assert catch_exit(FromXml.run([])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "Usage:"
    end

    test "shows error when only one file provided" do
      tmp_xml = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.xml")
      File.write!(tmp_xml, create_test_xml())

      try do
        assert catch_exit(FromXml.run([tmp_xml])) == {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Usage:"
      after
        File.rm(tmp_xml)
      end
    end

    test "shows error when input file not found" do
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")

      assert catch_exit(FromXml.run(["nonexistent.xml", tmp_dcm])) == {:shutdown, 1}

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "File not found"
    end

    test "shows error when template file not found" do
      tmp_xml = Path.join(System.tmp_dir!(), "input_#{:rand.uniform(100_000)}.xml")
      tmp_dcm = Path.join(System.tmp_dir!(), "output_#{:rand.uniform(100_000)}.dcm")
      File.write!(tmp_xml, create_test_xml())

      try do
        assert catch_exit(FromXml.run(["-t", "nonexistent.dcm", tmp_xml, tmp_dcm])) ==
                 {:shutdown, 1}

        assert_received {:mix_shell, :error, [message]}
        assert message =~ "Failed to read template"
      after
        File.rm(tmp_xml)
      end
    end
  end
end
