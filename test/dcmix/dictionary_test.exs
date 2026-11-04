defmodule Dcmix.DictionaryTest do
  use ExUnit.Case, async: true

  alias Dcmix.Dictionary

  doctest Dcmix.Dictionary

  describe "all/0" do
    test "is PS3.6's data dictionary, each entry with a keyword" do
      assert Dictionary.size() == 5303
      assert Enum.all?(Dictionary.all(), &(&1.keyword =~ ~r/\A[A-Za-z][A-Za-z0-9]*\z/))
    end

    test "gives every entry a VR dcmix reads and writes, or none" do
      assert Enum.all?(Dictionary.all(), &(is_nil(&1.vr) or Dcmix.VR.valid?(&1.vr)))
    end

    test "has no keyword twice" do
      entries = Dictionary.all()

      assert entries |> Enum.uniq_by(& &1.keyword) |> length() == length(entries)
    end

    test "has no tag twice, but for repeating groups whose first tag has an entry of its own" do
      # (0028,04x0) to (0028,04x3) start at TransformLabel and the tags after it
      repeating =
        ~w(RowsForNthOrderCoefficients ColumnsForNthOrderCoefficients CoefficientCoding CoefficientCodingPointers)

      entries = Enum.reject(Dictionary.all(), &(&1.keyword in repeating))

      assert entries |> Enum.uniq_by(& &1.tag) |> length() == length(entries)
    end
  end

  describe "lookup/1" do
    test "knows tags across groups, the code sequence tags among them" do
      for {tag, keyword, vr} <- [
            {{0x0008, 0x0100}, "CodeValue", :SH},
            {{0x0008, 0x0102}, "CodingSchemeDesignator", :SH},
            {{0x0008, 0x0104}, "CodeMeaning", :LO},
            {{0x0008, 0x002A}, "AcquisitionDateTime", :DT},
            {{0x0008, 0x0062}, "SOPClassesInStudy", :UI},
            {{0x0018, 0x0010}, "ContrastBolusAgent", :LO},
            {{0x0020, 0x0062}, "ImageLaterality", :CS},
            {{0x5200, 0x9230}, "PerFrameFunctionalGroupsSequence", :SQ},
            {{0x3006, 0x0020}, "StructureSetROISequence", :SQ}
          ] do
        assert {:ok, %{keyword: ^keyword, vr: ^vr}} = Dictionary.lookup(tag)
      end
    end

    test "knows retired tags" do
      assert {:ok, %{keyword: "LengthToEnd", vr: :UL}} = Dictionary.lookup({0x0008, 0x0001})
    end

    test "has the numbers and VRs PS3.6 gives" do
      assert Dictionary.tag("TemplateVersion") == {0x0040, 0xDB06}
      assert Dictionary.tag("HL7InstanceIdentifier") == {0x0040, 0xE001}
      assert Dictionary.keyword({0x0040, 0xDB73}) == "ReferencedContentItemIdentifier"
      assert Dictionary.vr({0x0070, 0x0042}) == :US
    end

    test "matches a repeating group's tag in any of its even groups" do
      assert {:ok, %{tag: {0x601E, 0x3000}, keyword: "OverlayData", vr: :OW}} =
               Dictionary.lookup({0x601E, 0x3000})

      assert Dictionary.keyword({0x5004, 0x0010}) == "NumberOfPoints"
      assert Dictionary.keyword({0x0020, 0x3105}) == "SourceImageIDs"
      assert Dictionary.keyword({0x1000, 0x0123}) == "HuffmanTableTriplet"
    end

    test "leaves a private tag alone, though its group fits a repeating group's pattern" do
      assert Dictionary.lookup({0x6001, 0x0010}) == {:error, :not_found}
    end

    test "prefers a tag's own entry to a repeating group whose pattern covers it" do
      assert Dictionary.keyword({0x0028, 0x0400}) == "TransformLabel"
    end

    test "gives a tag with more than one VR the one implicit VR data is read with" do
      # OB or OW
      assert Dictionary.vr({0x7FE0, 0x0010}) == :OW
      assert Dictionary.vr({0x5400, 0x1010}) == :OW
      # US or SS
      assert Dictionary.vr({0x0028, 0x0106}) == :US
      # US or OW
      assert {:ok, %{vr: :US, vm: "1-n"}} = Dictionary.lookup({0x0028, 0x3006})
    end
  end

  describe "tag/1" do
    test "gives a repeating group's first group" do
      assert Dictionary.tag("OverlayRows") == {0x6000, 0x0010}
    end
  end
end
