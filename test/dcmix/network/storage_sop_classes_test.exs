defmodule Dcmix.Network.StorageSOPClassesTest do
  use ExUnit.Case, async: true

  alias Dcmix.Network.StorageSOPClasses

  doctest StorageSOPClasses

  describe "uids/0" do
    test "is 120 classes, so a C-GET's contexts fit in an association" do
      assert length(StorageSOPClasses.uids()) == 120
    end
  end

  describe "accepted_uids/0" do
    test "is uids/0 and every SR Storage SOP Class, each once" do
      accepted = StorageSOPClasses.accepted_uids()
      sr = Enum.filter(accepted, &String.starts_with?(&1, "1.2.840.10008.5.1.4.1.1.88."))

      assert StorageSOPClasses.uids() -- accepted == []
      assert length(sr) == 24
      assert Enum.uniq(accepted) == accepted
    end
  end

  describe "classes/0" do
    test "pairs each class accepted with its PS3.6 keyword" do
      assert Enum.map(StorageSOPClasses.classes(), &elem(&1, 1)) ==
               StorageSOPClasses.accepted_uids()

      assert {"UltrasoundImageStorageRetired", "1.2.840.10008.5.1.4.1.1.6"} in StorageSOPClasses.classes()
    end
  end

  describe "keyword/1" do
    test "gives the PS3.6 keyword of the SR classes the C-GET list leaves out" do
      for {number, keyword} <- [
            {"1", "TextSRStorageTrial"},
            {"2", "AudioSRStorageTrial"},
            {"3", "DetailSRStorageTrial"},
            {"4", "ComprehensiveSRStorageTrial"},
            {"35", "ExtensibleSRStorage"},
            {"68", "RadiopharmaceuticalRadiationDoseSRStorage"},
            {"71", "AcquisitionContextSRStorage"},
            {"72", "SimplifiedAdultEchoSRStorage"},
            {"73", "PatientRadiationDoseSRStorage"},
            {"74", "PlannedImagingAgentAdministrationSRStorage"},
            {"75", "PerformedImagingAgentAdministrationSRStorage"},
            {"76", "EnhancedXRayRadiationDoseSRStorage"},
            {"77", "WaveformAnnotationSRStorage"}
          ] do
        assert StorageSOPClasses.keyword("1.2.840.10008.5.1.4.1.1.88.#{number}") == keyword
      end
    end

    test "gives the PS3.6 keyword of every class accepted" do
      for {keyword, uid} <- StorageSOPClasses.classes() do
        assert StorageSOPClasses.keyword(uid) == keyword
      end
    end

    test "is nil for a UID it doesn't know" do
      assert StorageSOPClasses.keyword("1.2.3") == nil
    end
  end
end
