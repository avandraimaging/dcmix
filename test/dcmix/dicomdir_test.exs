defmodule Dcmix.DicomdirTest do
  use ExUnit.Case, async: true

  alias Dcmix.{DataSet, Dicomdir}

  doctest Dcmix.Dicomdir

  @ct "1.2.840.10008.5.1.4.1.1.2"
  @explicit_vr_little_endian "1.2.840.10008.1.2.1"

  describe "encode/2: the tree" do
    test "a reader following the offsets finds every patient, study, series and instance" do
      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000), study: "1.2.9.1", series: "1.2.9.1.1"),
        instance(~w(DICOM ST000000 SE000000 IN000001), study: "1.2.9.1", series: "1.2.9.1.1"),
        instance(~w(DICOM ST000000 SE000001 IN000000), study: "1.2.9.1", series: "1.2.9.1.2"),
        instance(~w(DICOM ST000001 SE000000 IN000000), study: "1.2.9.2", series: "1.2.9.2.1")
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)

      assert walk(bytes) == [
               {"PATIENT", "FIXTURE-1",
                [
                  {"STUDY", "1.2.9.1",
                   [
                     {"SERIES", "1.2.9.1.1",
                      [
                        {"IMAGE", "DICOM\\ST000000\\SE000000\\IN000000", []},
                        {"IMAGE", "DICOM\\ST000000\\SE000000\\IN000001", []}
                      ]},
                     {"SERIES", "1.2.9.1.2",
                      [{"IMAGE", "DICOM\\ST000000\\SE000001\\IN000000", []}]}
                   ]},
                  {"STUDY", "1.2.9.2",
                   [
                     {"SERIES", "1.2.9.2.1",
                      [{"IMAGE", "DICOM\\ST000001\\SE000000\\IN000000", []}]}
                   ]}
                ]}
             ]
    end

    test "groups by the UIDs the instances carry, not the folders they sit in" do
      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000), study: "1.2.9.1", series: "1.2.9.1.1"),
        instance(~w(DICOM ST000001 SE000000 IN000000), study: "1.2.9.1", series: "1.2.9.1.1")
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      assert [{"PATIENT", _, [{"STUDY", _, [{"SERIES", _, [_, _]}]}]}] = walk(bytes)
    end

    test "keeps patients apart by Patient ID" do
      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000), study: "1.2.9.1"),
        instance(~w(DICOM ST000001 SE000000 IN000000),
          study: "1.2.9.2",
          extra: [{"PatientID", :LO, "FIXTURE-2"}]
        )
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      assert [{"PATIENT", "FIXTURE-1", _}, {"PATIENT", "FIXTURE-2", _}] = walk(bytes)
    end

    test "keeps patients nobody identified apart, by name" do
      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000),
          study: "1.2.9.1",
          extra: [{"PatientID", :LO, :absent}, {"PatientName", :PN, "First^Unidentified"}]
        ),
        instance(~w(DICOM ST000001 SE000000 IN000000),
          study: "1.2.9.2",
          extra: [{"PatientID", :LO, :absent}, {"PatientName", :PN, "Second^Unidentified"}]
        )
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      assert [{"PATIENT", "", [_study_1]}, {"PATIENT", "", [_study_2]}] = walk(bytes)

      assert ["First^Unidentified", "Second^Unidentified"] =
               bytes |> records() |> patient_names()
    end

    test "takes a Patient ID's leading spaces as insignificant" do
      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000),
          study: "1.2.9.1",
          extra: [{"PatientID", :LO, " FIXTURE-1"}]
        ),
        instance(~w(DICOM ST000001 SE000000 IN000000), study: "1.2.9.2")
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      assert [{"PATIENT", _, [_study_1, _study_2]}] = walk(bytes)
    end

    test "takes a patient record's keys from the first instance that names the patient" do
      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000), extra: [{"PatientName", :PN, :absent}]),
        instance(~w(DICOM ST000000 SE000000 IN000001),
          extra: [{"PatientName", :PN, "Named^Patient"}]
        )
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      assert ["Named^Patient"] = bytes |> records() |> patient_names()
    end

    test "reads an instance with pixel data, whose header is all it needs" do
      pixels = {"PixelData", :OW, :binary.copy(<<1, 2>>, 4096)}
      instances = [instance(~w(DICOM ST000000 SE000000 IN000000), extra: [pixels])]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      assert [{"PATIENT", _, [{"STUDY", _, [{"SERIES", _, [{"IMAGE", _, []}]}]}]}] = walk(bytes)
    end
  end

  describe "encode/2: the records" do
    test "an instance record names its file, SOP class, SOP instance and transfer syntax" do
      instances = [instance(~w(DICOM ST000000 SE000000 IN000000), sop_instance: "1.2.9.1.1.7")]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      [_patient, _study, _series, image] = records(bytes)

      assert Dcmix.get_string(image, "ReferencedFileID") == "DICOM\\ST000000\\SE000000\\IN000000"
      assert Dcmix.get_string(image, "ReferencedSOPClassUIDInFile") =~ @ct
      assert Dcmix.get_string(image, "ReferencedSOPInstanceUIDInFile") =~ "1.2.9.1.1.7"

      assert Dcmix.get_string(image, "ReferencedTransferSyntaxUIDInFile") =~
               @explicit_vr_little_endian
    end

    test "the SOP class decides the record type" do
      classes = [
        {"1.2.840.10008.5.1.4.1.1.88.22", "SR DOCUMENT"},
        {"1.2.840.10008.5.1.4.1.1.88.59", "KEY OBJECT DOC"},
        {"1.2.840.10008.5.1.4.1.1.78.6", "SR DOCUMENT"},
        {"1.2.840.10008.5.1.4.1.1.78.1", "MEASUREMENT"},
        {"1.2.840.10008.5.1.4.1.1.11.1", "PRESENTATION"},
        {"1.2.840.10008.5.1.4.1.1.104.1", "ENCAP DOC"},
        {"1.2.840.10008.5.1.4.1.1.481.6", "RT TREAT RECORD"},
        {"1.2.840.10008.5.1.4.1.1.481.8", "RT PLAN"},
        {"1.2.840.10008.5.1.4.1.1.4.2", "SPECTROSCOPY"},
        {"1.2.840.10008.5.1.4.1.1.66", "RAW DATA"},
        {"1.2.840.10008.5.1.4.1.1.66.1", "REGISTRATION"},
        {"1.2.840.10008.5.1.4.1.1.67", "VALUE MAP"},
        {@ct, "IMAGE"}
      ]

      instances =
        for {{sop_class, _type}, n} <- Enum.with_index(classes) do
          instance(["DICOM", "ST000000", "SE000000", "IN#{String.pad_leading("#{n}", 6, "0")}"],
            sop_class: sop_class
          )
        end

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      [{"PATIENT", _, [{"STUDY", _, [{"SERIES", _, leaves}]}]}] = walk(bytes)

      assert Enum.map(leaves, &elem(&1, 0)) == Enum.map(classes, &elem(&1, 1))
    end

    test "each record type carries every key PS3.3 Annex F requires of it" do
      content =
        ~w(ContentDate ContentTime InstanceNumber ContentLabel ContentDescription ContentCreatorName)

      expected = [
        {"1.2.840.10008.5.1.4.1.1.9.1.1", ~w(InstanceNumber ContentDate ContentTime)},
        {"1.2.840.10008.5.1.4.1.1.66", ~w(InstanceNumber ContentDate ContentTime)},
        {"1.2.840.10008.5.1.4.1.1.66.1", content},
        {"1.2.840.10008.5.1.4.1.1.66.2", content},
        {"1.2.840.10008.5.1.4.1.1.66.5", content},
        {"1.2.840.10008.5.1.4.1.1.66.6", content},
        {"1.2.840.10008.5.1.4.1.1.67", content},
        {"1.2.840.10008.5.1.4.1.1.78.1", content},
        {"1.2.840.10008.5.1.4.1.1.68.1", ~w(ContentDate ContentTime)},
        {"1.2.840.10008.5.1.4.1.1.90.1",
         ~w(InstanceNumber InstanceCreationDate InstanceCreationTime)},
        {"1.2.840.10008.5.1.4.1.1.11.1",
         ~w(InstanceNumber ContentLabel ContentDescription ContentCreatorName PresentationCreationDate PresentationCreationTime)},
        {"1.2.840.10008.5.1.4.1.1.88.22",
         ~w(InstanceNumber CompletionFlag VerificationFlag ContentDate ContentTime)},
        {"1.2.840.10008.5.1.4.1.1.88.59", ~w(InstanceNumber ContentDate ContentTime)},
        {"1.2.840.10008.5.1.4.1.1.481.2", ~w(InstanceNumber DoseSummationType)},
        {"1.2.840.10008.5.1.4.1.1.481.3",
         ~w(InstanceNumber StructureSetLabel StructureSetDate StructureSetTime)},
        {"1.2.840.10008.5.1.4.1.1.481.5", ~w(InstanceNumber RTPlanLabel RTPlanDate RTPlanTime)},
        {"1.2.840.10008.5.1.4.1.1.481.4", ~w(InstanceNumber TreatmentDate TreatmentTime)},
        {"1.2.840.10008.5.1.4.1.1.104.1",
         ~w(InstanceNumber ContentDate ContentTime DocumentTitle MIMETypeOfEncapsulatedDocument ConceptNameCodeSequence)},
        {@ct, ~w(InstanceNumber)}
      ]

      for {sop_class, keys} <- expected do
        instances = [instance(~w(DICOM ST000000 SE000000 IN000000), sop_class: sop_class)]

        assert {:ok, bytes, []} = Dicomdir.encode(instances)
        [_patient, _study, _series, record] = records(bytes)

        assert {sop_class, Enum.sort(keys -- keys_of(record))} == {sop_class, []}
      end
    end

    test "copies an instance's values into its record" do
      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000),
          sop_class: "1.2.840.10008.5.1.4.1.1.481.5",
          extra: [{"RTPlanLabel", :SH, "BREAST L"}, {"RTPlanDate", :DA, "20261029"}]
        )
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      [_patient, _study, _series, plan] = records(bytes)

      assert Dcmix.get_string(plan, "RTPlanLabel") == "BREAST L"
      assert Dcmix.get_string(plan, "RTPlanDate") == "20261029"
    end

    test "a key every record of its type needs is written empty when the instance lacks it" do
      instances = [instance(~w(DICOM ST000000 SE000000 IN000000))]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      [_patient, study, _series, _image] = records(bytes)

      assert Dcmix.get_element(study, "StudyID")
      assert Dcmix.get_string(study, "StudyID") in [nil, ""]
    end

    test "a key a study browser only shows is left out when the instance lacks it" do
      instances = [instance(~w(DICOM ST000000 SE000000 IN000000))]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      [patient, _study, _series, _image] = records(bytes)

      refute Dcmix.get_element(patient, "PatientBirthDate")
    end

    test "writes a spectroscopy record's numbers as numbers, and leaves out one it lacks" do
      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000),
          sop_class: "1.2.840.10008.5.1.4.1.1.4.2",
          extra: [{"Rows", :US, 16}, {"Columns", :US, 16}, {"DataPointRows", :UL, 1}]
        )
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      [_patient, _study, _series, spectroscopy] = records(bytes)

      assert value(spectroscopy, "Rows") == 16
      assert value(spectroscopy, "DataPointRows") == 1
      refute Dcmix.get_element(spectroscopy, "DataPointColumns")
    end

    test "a verified SR record carries its latest verification" do
      observer = &Dcmix.put(Dcmix.new(), "VerificationDateTime", :DT, &1)
      sr = "1.2.840.10008.5.1.4.1.1.88.22"

      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000),
          sop_class: sr,
          extra: [
            {"VerificationFlag", :CS, "VERIFIED"},
            {"VerifyingObserverSequence", :SQ,
             [observer.("20261028090000"), observer.("20261029101500")]}
          ]
        ),
        instance(~w(DICOM ST000000 SE000000 IN000001),
          sop_class: sr,
          extra: [{"VerificationFlag", :CS, "UNVERIFIED"}]
        )
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      [_patient, _study, _series, verified, unverified] = records(bytes)

      assert Dcmix.get_string(verified, "VerificationDateTime") == "20261029101500"
      refute Dcmix.get_element(unverified, "VerificationDateTime")
    end
  end

  describe "encode/2: text" do
    test "copies text as the instance has it, under the instance's character set" do
      latin1_name = <<"PE", 0xD1, "A^JOS", 0xC9>>

      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000),
          extra: [{"SpecificCharacterSet", :CS, "ISO_IR 100"}, {"PatientName", :PN, latin1_name}]
        )
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      [patient, _study, _series, _image] = records(bytes)

      assert Dcmix.get_string(patient, "SpecificCharacterSet") == "ISO_IR 100"
      assert Dcmix.get_string(patient, "PatientName") == latin1_name
    end

    test "declares no character set for an instance that declares none" do
      instances = [instance(~w(DICOM ST000000 SE000000 IN000000))]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      [patient, _study, _series, _image] = records(bytes)

      refute Dcmix.get_element(patient, "SpecificCharacterSet")
    end
  end

  describe "encode/2: what it leaves out" do
    test "an instance lacking a UID that places it, reported by its File ID" do
      instances = [
        instance(~w(DICOM ST000000 SE000000 IN000000), series: :absent),
        instance(~w(DICOM ST000000 SE000000 IN000001))
      ]

      assert {:ok, bytes, [~w(DICOM ST000000 SE000000 IN000000)]} = Dicomdir.encode(instances)

      assert [{"PATIENT", _, [{"STUDY", _, [{"SERIES", _, [{"IMAGE", file_id, []}]}]}]}] =
               walk(bytes)

      assert file_id == "DICOM\\ST000000\\SE000000\\IN000001"
    end

    test "refuses when nothing is left to refer to" do
      instances = [instance(~w(DICOM ST000000 SE000000 IN000000), study: :absent)]

      assert Dicomdir.encode(instances) == {:error, :no_instances}
    end
  end

  describe "encode/2: options" do
    test "the same instances and options encode to the same bytes" do
      instances = [instance(~w(DICOM ST000000 SE000000 IN000000))]

      opts = [
        file_set_uid: "2.25.1234",
        file_set_id: "SHARE",
        implementation_version_name: "PINNED"
      ]

      assert {:ok, bytes, []} = Dicomdir.encode(instances, opts)
      assert Dicomdir.encode(instances, opts) == {:ok, bytes, []}

      assert {:ok, dicomdir} = Dcmix.Parser.parse(bytes)
      assert Dcmix.get_string(dicomdir, "MediaStorageSOPClassUID") =~ "1.2.840.10008.1.3.10"
      assert Dcmix.get_string(dicomdir, "MediaStorageSOPInstanceUID") =~ "2.25.1234"
      assert Dcmix.get_string(dicomdir, "ImplementationVersionName") == "PINNED"
      assert Dcmix.get_string(dicomdir, "FileSetID") == "SHARE"
    end

    test "generates a file-set UID, and names dcmix's version, unless told otherwise" do
      instances = [instance(~w(DICOM ST000000 SE000000 IN000000))]

      assert {:ok, bytes, []} = Dicomdir.encode(instances)
      assert {:ok, dicomdir} = Dcmix.Parser.parse(bytes)

      assert Dcmix.get_string(dicomdir, "MediaStorageSOPInstanceUID") =~ Dcmix.UID.root()

      assert Dcmix.get_string(dicomdir, "ImplementationVersionName") ==
               Dcmix.UID.implementation_version_name()
    end
  end

  # An instance read back from a written file, as `{file_id, data_set}`, so it
  # carries a File Meta header. `:study`, `:series`, `:sop_class` and
  # `:sop_instance` set those UIDs (`:absent` leaves one out); `:extra` adds
  # any other elements as `{keyword, vr, value}`.
  defp instance(file_id, opts \\ []) do
    study = Keyword.get(opts, :study, "1.2.9.1")
    series = Keyword.get(opts, :series, "#{study}.1")

    sop_instance =
      Keyword.get(
        opts,
        :sop_instance,
        ("1.2.9." <> Enum.join(file_id)) |> String.replace(~r/\D/, "")
      )

    data_set =
      [
        {"SOPClassUID", :UI, Keyword.get(opts, :sop_class, @ct)},
        {"SOPInstanceUID", :UI, sop_instance},
        {"PatientName", :PN, "Fictional^Patient"},
        {"PatientID", :LO, "FIXTURE-1"},
        {"StudyInstanceUID", :UI, study},
        {"SeriesInstanceUID", :UI, series},
        {"Modality", :CS, "OT"}
      ]
      |> Enum.concat(Keyword.get(opts, :extra, []))
      |> Enum.reverse()
      |> Enum.uniq_by(fn {keyword, _vr, _value} -> keyword end)
      |> Enum.reverse()
      |> Enum.reject(fn {_keyword, _vr, value} -> value == :absent end)
      |> Enum.reduce(Dcmix.new(), fn {keyword, vr, value}, data_set ->
        Dcmix.put(data_set, keyword, vr, value)
      end)

    {:ok, encoded} = Dcmix.Writer.encode(data_set)
    {:ok, read} = Dcmix.Parser.parse(encoded, stop_before_pixels: true)
    {file_id, read}
  end

  # The tree as a reader finds it: from the root's first record, following each
  # record's next and lower-level offsets, as `{type, identity, children}`.
  defp walk(bytes) do
    {:ok, dicomdir} = Dcmix.Parser.parse(bytes)
    siblings(bytes, value(dicomdir, "OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity"))
  end

  defp siblings(_bytes, 0), do: []

  defp siblings(bytes, offset) do
    record = record_at(bytes, offset)
    children = siblings(bytes, value(record, "OffsetOfReferencedLowerLevelDirectoryEntity"))

    [
      {type(record), identity(record), children}
      | siblings(bytes, value(record, "OffsetOfTheNextDirectoryRecord"))
    ]
  end

  # The record whose item starts exactly at `offset`, or a failed match.
  defp record_at(bytes, offset) do
    <<_before::binary-size(^offset), 0xFE, 0xFF, 0x00, 0xE0, length::32-little,
      item::binary-size(length), _after::binary>> = bytes

    {:ok, record} = Dcmix.Parser.parse(item)
    record
  end

  defp type(record), do: record |> Dcmix.get_string("DirectoryRecordType") |> String.trim()

  defp identity(record) do
    case type(record) do
      "PATIENT" -> Dcmix.get_string(record, "PatientID")
      "STUDY" -> Dcmix.get_string(record, "StudyInstanceUID") |> String.trim_trailing(<<0>>)
      "SERIES" -> Dcmix.get_string(record, "SeriesInstanceUID") |> String.trim_trailing(<<0>>)
      _instance -> Dcmix.get_string(record, "ReferencedFileID")
    end
  end

  # Every record, in the order they sit in the file.
  defp records(bytes) do
    {:ok, dicomdir} = Dcmix.Parser.parse(bytes)
    value(dicomdir, "DirectoryRecordSequence")
  end

  defp patient_names(records) do
    for record <- records, type(record) == "PATIENT", do: Dcmix.get_string(record, "PatientName")
  end

  # The keywords a record carries besides the DICOMDIR's own (group 0004) and
  # its character set.
  defp keys_of(record) do
    for %{tag: {group, _element} = tag} <- DataSet.to_list(record),
        group != 0x0004,
        keyword = Dcmix.Dictionary.keyword(tag),
        keyword != "SpecificCharacterSet",
        do: keyword
  end

  defp value(data_set, keyword), do: Dcmix.get_element(data_set, keyword).value
end
