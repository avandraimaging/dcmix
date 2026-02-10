defmodule Dcmix.Network.QueryTest do
  use ExUnit.Case, async: true

  alias Dcmix.DataSet
  alias Dcmix.Network.Query

  @query_retrieve_level {0x0008, 0x0052}
  @patient_name {0x0010, 0x0010}
  @patient_id {0x0010, 0x0020}
  @study_date {0x0008, 0x0020}
  @study_time {0x0008, 0x0030}
  @study_instance_uid {0x0020, 0x000D}

  describe "parse_terms/1" do
    test "parses bare keyword as empty match value" do
      assert {:ok, ds} = Query.parse_terms(["PatientName"])
      assert DataSet.get_string(ds, @patient_name) == ""
    end

    test "parses keyword=value" do
      assert {:ok, ds} = Query.parse_terms(["StudyDate=20250708"])
      assert DataSet.get_string(ds, @study_date) == "20250708"
    end

    test "handles time range values" do
      assert {:ok, ds} = Query.parse_terms(["StudyTime=070000-073000"])
      assert DataSet.get_string(ds, @study_time) == "070000-073000"
    end

    test "adds QueryRetrieveLevel=STUDY when missing" do
      assert {:ok, ds} = Query.parse_terms(["PatientName"])
      assert DataSet.get_string(ds, @query_retrieve_level) == "STUDY"
    end

    test "does not override explicit QueryRetrieveLevel" do
      assert {:ok, ds} = Query.parse_terms(["QueryRetrieveLevel=PATIENT", "PatientName"])
      assert DataSet.get_string(ds, @query_retrieve_level) == "PATIENT"
    end

    test "later value overrides earlier for same keyword" do
      assert {:ok, ds} = Query.parse_terms(["StudyDate", "StudyDate=20250708"])
      assert DataSet.get_string(ds, @study_date) == "20250708"
    end

    test "returns error for unknown keyword" do
      assert {:error, {:unknown_keyword, "NotARealTag"}} = Query.parse_terms(["NotARealTag"])
    end

    test "handles mender-style full query" do
      terms = [
        "StudyInstanceUID",
        "PatientName",
        "PatientID",
        "PatientBirthDate",
        "PatientSex",
        "InstitutionName",
        "AccessionNumber",
        "ModalitiesInStudy",
        "StudyDescription",
        "StudyDate",
        "StudyTime",
        "PatientAge",
        "PatientOrientation",
        "NumberOfStudyRelatedInstances",
        "StudyDate=20250708",
        "StudyTime=070000-073000"
      ]

      assert {:ok, ds} = Query.parse_terms(terms)

      # Bare keywords should have empty values
      assert DataSet.get_string(ds, @patient_name) == ""
      assert DataSet.get_string(ds, @patient_id) == ""
      assert DataSet.get_string(ds, @study_instance_uid) == ""

      # Keywords with values should have them
      assert DataSet.get_string(ds, @study_date) == "20250708"
      assert DataSet.get_string(ds, @study_time) == "070000-073000"

      # Should auto-add QR level
      assert DataSet.get_string(ds, @query_retrieve_level) == "STUDY"
    end

    test "handles multiple keywords with values" do
      assert {:ok, ds} =
               Query.parse_terms(["PatientName=Smith*", "PatientID=12345"])

      assert DataSet.get_string(ds, @patient_name) == "Smith*"
      assert DataSet.get_string(ds, @patient_id) == "12345"
    end

    test "preserves correct VR for each tag" do
      assert {:ok, ds} = Query.parse_terms(["PatientName", "StudyDate"])

      pn_element = DataSet.get(ds, @patient_name)
      assert pn_element.vr == :PN

      da_element = DataSet.get(ds, @study_date)
      assert da_element.vr == :DA
    end

    test "handles empty list" do
      assert {:ok, ds} = Query.parse_terms([])
      # Should only have QueryRetrieveLevel
      assert DataSet.size(ds) == 1
      assert DataSet.get_string(ds, @query_retrieve_level) == "STUDY"
    end

    test "stops on first error" do
      result = Query.parse_terms(["PatientName", "InvalidTag", "StudyDate"])
      assert {:error, {:unknown_keyword, "InvalidTag"}} = result
    end
  end

  describe "parse_term/1" do
    test "parses bare keyword" do
      assert {:ok, {@patient_name, :PN, ""}} = Query.parse_term("PatientName")
    end

    test "parses keyword with value" do
      assert {:ok, {@study_date, :DA, "20250708"}} = Query.parse_term("StudyDate=20250708")
    end

    test "handles value containing equals sign" do
      # Unlikely but edge case: value itself contains =
      assert {:ok, {_tag, _vr, "foo=bar"}} = Query.parse_term("PatientName=foo=bar")
    end

    test "returns error for unknown keyword" do
      assert {:error, {:unknown_keyword, "BogusTag"}} = Query.parse_term("BogusTag")
    end
  end
end
