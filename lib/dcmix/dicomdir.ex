defmodule Dcmix.Dicomdir do
  @moduledoc """
  Writes a DICOMDIR: the index a viewer reads to list the patients, studies,
  series and instances in a file set without opening every file, as dcmtk's
  `dcmmkdir` does.

  ## Usage

      {:ok, header} = Dcmix.read_file(path, stop_before_pixels: true)
      {:ok, dicomdir, _left_out} = Dcmix.Dicomdir.encode([{["DICOM", "IM000001"], header}])

  Each instance is given as its File ID, the path components the file sits at
  under the DICOMDIR, and its data set. Only the header is read, so a data set
  read with `stop_before_pixels: true` is enough.

  ## Records

  Patients, studies and series are grouped by the Patient ID, Study Instance
  UID and Series Instance UID their instances carry, in the order the instances
  are given. Instances with no Patient ID are grouped by Patient Name instead,
  so patients nobody identified stay apart; their record's Patient ID is empty,
  since dcmix doesn't invent one. A patient record takes its keys from the
  first instance in its group that names the patient. Each instance's record
  type comes from its SOP class, and each
  record carries the keys PS3.3 Annex F requires of its type. A required key
  the instance has no value for is written empty, except a number, which can't
  be. Sequences aren't copied: a required one is written empty.

  Values are copied as the instance has them, and each record declares the
  Specific Character Set of the instance it came from, which Annex F allows
  record by record. So text needs no conversion.

  ## Offsets

  Records point at their next sibling and their first child by byte offset
  from the start of the file. Each record is written as a sequence item with
  its length up front, so a record's position is the sum of the encoded sizes
  before it, and an offset takes four bytes whatever its value. So every record
  is sized with zero offsets, positioned, then encoded with the real ones.
  """

  alias Dcmix.{DataSet, UID, Writer}
  alias Dcmix.Writer.ExplicitVR

  @typedoc "A File ID: the path components of a file under the DICOMDIR."
  @type file_id :: [String.t()]

  @media_storage_directory "1.2.840.10008.1.3.10"
  @explicit_vr_little_endian "1.2.840.10008.1.2.1"

  # The record sequence's delimiter, which follows the last record.
  @sequence_delimiter_bytes 8
  # An item's tag and length, ahead of the record it holds.
  @item_header_bytes 8

  # What each record carries from the instance it was read from, per PS3.3
  # Annex F. A key the record type requires is written empty when the instance
  # has no value; one a study browser only shows is written when it does.
  @patient_keys [
    {"PatientName", :PN, :always},
    {"PatientID", :LO, :always},
    {"PatientBirthDate", :DA, :when_present},
    {"PatientSex", :CS, :when_present}
  ]

  @study_keys [
    {"StudyDate", :DA, :always},
    {"StudyTime", :TM, :always},
    {"AccessionNumber", :SH, :always},
    {"StudyDescription", :LO, :always},
    {"StudyInstanceUID", :UI, :always},
    {"StudyID", :SH, :always}
  ]

  @series_keys [
    {"Modality", :CS, :always},
    {"SeriesDescription", :LO, :when_present},
    {"SeriesInstanceUID", :UI, :always},
    {"SeriesNumber", :IS, :always}
  ]

  @instance_number {"InstanceNumber", :IS, :always}
  @content_date {"ContentDate", :DA, :always}
  @content_time {"ContentTime", :TM, :always}

  # The Content Identification Macro's keys, after Instance Number.
  @content_identification [
    {"ContentLabel", :CS, :always},
    {"ContentDescription", :LO, :always},
    {"ContentCreatorName", :PN, :always}
  ]

  @content_keys [@content_date, @content_time, @instance_number | @content_identification]

  @sop_class "1.2.840.10008.5.1.4.1.1."

  # The record type an instance's SOP class takes, after pydicom's table. A
  # class ending in a dot matches every class under it; the first match wins,
  # so a class is listed before the family it belongs to. Anything unlisted is
  # an IMAGE.
  @record_types [
    {@sop_class <> "88.59", "KEY OBJECT DOC"},
    {@sop_class <> "88.", "SR DOCUMENT"},
    {@sop_class <> "78.6", "SR DOCUMENT"},
    {@sop_class <> "79.1", "SR DOCUMENT"},
    {@sop_class <> "11.", "PRESENTATION"},
    {@sop_class <> "131", "PRESENTATION"},
    {@sop_class <> "104.", "ENCAP DOC"},
    {@sop_class <> "9.", "WAVEFORM"},
    {@sop_class <> "481.2", "RT DOSE"},
    {@sop_class <> "481.3", "RT STRUCTURE SET"},
    {@sop_class <> "481.4", "RT TREAT RECORD"},
    {@sop_class <> "481.5", "RT PLAN"},
    {@sop_class <> "481.6", "RT TREAT RECORD"},
    {@sop_class <> "481.7", "RT TREAT RECORD"},
    {@sop_class <> "481.8", "RT PLAN"},
    {@sop_class <> "481.9", "RT TREAT RECORD"},
    {@sop_class <> "4.2", "SPECTROSCOPY"},
    {@sop_class <> "66", "RAW DATA"},
    {@sop_class <> "66.1", "REGISTRATION"},
    {@sop_class <> "66.2", "FIDUCIAL"},
    {@sop_class <> "66.3", "REGISTRATION"},
    {@sop_class <> "66.5", "SURFACE"},
    {@sop_class <> "66.6", "TRACT"},
    {@sop_class <> "67", "VALUE MAP"},
    {@sop_class <> "68.1", "SURFACE SCAN"},
    {@sop_class <> "68.2", "SURFACE SCAN"},
    {@sop_class <> "77.1.5.3", "STEREOMETRIC"},
    {@sop_class <> "78.", "MEASUREMENT"},
    {@sop_class <> "80.1", "MEASUREMENT"},
    {@sop_class <> "90.1", "ASSESSMENT"}
  ]

  @instance_keys %{
    "SR DOCUMENT" => [
      @instance_number,
      {"CompletionFlag", :CS, :always},
      {"VerificationFlag", :CS, :always},
      @content_date,
      @content_time,
      {"VerificationDateTime", :DT, :when_present}
    ],
    "KEY OBJECT DOC" => [@instance_number, @content_date, @content_time],
    "PRESENTATION" =>
      [@instance_number | @content_identification] ++
        [
          {"PresentationCreationDate", :DA, :always},
          {"PresentationCreationTime", :TM, :always}
        ],
    "ENCAP DOC" => [
      @instance_number,
      @content_date,
      @content_time,
      {"DocumentTitle", :ST, :always},
      {"MIMETypeOfEncapsulatedDocument", :LO, :always},
      {"ConceptNameCodeSequence", :SQ, :always}
    ],
    "WAVEFORM" => [@instance_number, @content_date, @content_time],
    "RAW DATA" => [@instance_number, @content_date, @content_time],
    "REGISTRATION" => @content_keys,
    "FIDUCIAL" => @content_keys,
    "SURFACE" => @content_keys,
    "VALUE MAP" => @content_keys,
    "MEASUREMENT" => @content_keys,
    "TRACT" => @content_keys,
    "SURFACE SCAN" => [@content_date, @content_time],
    "ASSESSMENT" => [
      @instance_number,
      {"InstanceCreationDate", :DA, :always},
      {"InstanceCreationTime", :TM, :always}
    ],
    "RT DOSE" => [@instance_number, {"DoseSummationType", :CS, :always}],
    "RT STRUCTURE SET" => [
      @instance_number,
      {"StructureSetLabel", :SH, :always},
      {"StructureSetDate", :DA, :always},
      {"StructureSetTime", :TM, :always}
    ],
    "RT PLAN" => [
      @instance_number,
      {"RTPlanLabel", :SH, :always},
      {"RTPlanDate", :DA, :always},
      {"RTPlanTime", :TM, :always}
    ],
    "RT TREAT RECORD" => [
      @instance_number,
      {"TreatmentDate", :DA, :always},
      {"TreatmentTime", :TM, :always}
    ],
    "SPECTROSCOPY" => [
      {"ImageType", :CS, :always},
      @content_date,
      @content_time,
      @instance_number,
      {"NumberOfFrames", :IS, :always},
      {"Rows", :US, :always},
      {"Columns", :US, :always},
      {"DataPointRows", :UL, :always},
      {"DataPointColumns", :UL, :always}
    ]
  }

  # IMAGE, and STEREOMETRIC, whose record defines no keys of its own.
  @other_instance_keys [
    @instance_number,
    {"ContentDate", :DA, :when_present},
    {"ContentTime", :TM, :when_present}
  ]

  @placing_uids ["StudyInstanceUID", "SeriesInstanceUID", "SOPClassUID", "SOPInstanceUID"]

  @doc """
  Encodes the DICOMDIR for `instances`, `{file_id, data_set}` pairs.

  Returns `{:ok, dicomdir, left_out}`, where `left_out` lists the File IDs of
  instances it couldn't refer to: those lacking the Study Instance, Series
  Instance, SOP Class or SOP Instance UID that place them. Returns
  `{:error, :no_instances}` when that is all of them.

  ## Options
  - `:file_set_uid` - the DICOMDIR's Media Storage SOP Instance UID (default:
    a generated one)
  - `:file_set_id` - File-set ID (0004,1130) (default: empty)
  - `:implementation_version_name` - Implementation Version Name (0002,0013)
    (default: dcmix's, which changes with its version)
  """
  @spec encode([{file_id(), DataSet.t()}], keyword()) ::
          {:ok, binary(), [file_id()]} | {:error, :no_instances}
  def encode(instances, opts \\ []) do
    {entries, left_out} =
      Enum.reduce(instances, {[], []}, fn {file_id, data_set}, {entries, left_out} ->
        case entry(file_id, data_set) do
          nil -> {entries, [file_id | left_out]}
          entry -> {[entry | entries], left_out}
        end
      end)

    case Enum.reverse(entries) do
      [] -> {:error, :no_instances}
      entries -> {:ok, encode_file(patients(entries), opts), Enum.reverse(left_out)}
    end
  end

  @doc """
  The Directory Record Type (0004,1430) an instance of `sop_class_uid` takes.

      iex> Dcmix.Dicomdir.record_type("1.2.840.10008.5.1.4.1.1.88.22")
      "SR DOCUMENT"

      iex> Dcmix.Dicomdir.record_type("1.2.840.10008.5.1.4.1.1.2")
      "IMAGE"
  """
  @spec record_type(String.t()) :: String.t()
  def record_type(sop_class_uid) do
    Enum.find_value(@record_types, "IMAGE", fn {uid, type} ->
      if uid == sop_class_uid or
           (String.ends_with?(uid, ".") and String.starts_with?(sop_class_uid, uid)),
         do: type
    end)
  end

  defp entry(file_id, data_set) do
    case Enum.map(@placing_uids, &text(data_set, &1)) do
      [study, series, sop_class, sop_instance]
      when is_binary(study) and is_binary(series) and is_binary(sop_class) and
             is_binary(sop_instance) ->
        type = record_type(sop_class)

        %{
          file_id: file_id,
          patient: patient(data_set),
          named?: patient_name(data_set) != "",
          study: study,
          series: series,
          sop_class: sop_class,
          sop_instance: sop_instance,
          transfer_syntax: text(data_set, "TransferSyntaxUID") || @explicit_vr_little_endian,
          character_set: text(data_set, "SpecificCharacterSet"),
          type: type,
          values: values(data_set, type)
        }

      _unplaceable ->
        nil
    end
  end

  defp values(data_set, type) do
    keys = @patient_keys ++ @study_keys ++ @series_keys ++ instance_keys(type)

    values =
      for {keyword, vr, _presence} <- keys, into: %{}, do: {keyword, value(data_set, keyword, vr)}

    if type == "SR DOCUMENT",
      do: Map.put(values, "VerificationDateTime", verification_date_time(data_set)),
      else: values
  end

  # Sequences aren't copied, so a sequence key is written empty.
  defp value(_data_set, _keyword, :SQ), do: nil

  defp value(data_set, keyword, vr) when vr in [:US, :UL] do
    case Dcmix.get_element(data_set, keyword) do
      %{value: number} when is_integer(number) -> number
      _absent -> nil
    end
  end

  defp value(data_set, keyword, _vr), do: text(data_set, keyword)

  # A value as its bytes, less the padding, or nil when there is none. Not
  # decoded: the record declares the instance's character set instead.
  defp text(data_set, keyword) do
    case Dcmix.get_element(data_set, keyword) do
      %{value: value} when is_binary(value) ->
        blank_to_nil(String.trim_trailing(value, " ") |> String.trim_trailing(<<0>>))

      %{value: [_ | _] = values} ->
        blank_to_nil(Enum.join(values, "\\"))

      _absent ->
        nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # An SR record needs the latest verification when the document is verified,
  # which the instance keeps on each of its verifying observers.
  defp verification_date_time(data_set) do
    with "VERIFIED" <- text(data_set, "VerificationFlag"),
         %{value: [_ | _] = observers} <- Dcmix.get_element(data_set, "VerifyingObserverSequence") do
      observers
      |> Enum.map(&text(&1, "VerificationDateTime"))
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> nil end)
    else
      _unverified -> nil
    end
  end

  defp instance_keys(type), do: Map.get(@instance_keys, type, @other_instance_keys)

  # The tree, in the order the instances came: each level grouped by the UID
  # that identifies it, so a study split across oddly numbered folders is still
  # one study.
  defp patients(entries) do
    for {_patient, patient} <- grouped(entries, & &1.patient) do
      source = Enum.find(patient, hd(patient), & &1.named?)
      node(record("PATIENT", source, @patient_keys), studies(patient))
    end
  end

  # Leading spaces in an LO are insignificant, so " P1" is the same patient
  # as "P1". Only the space is trimmed: the bytes are in the instance's own
  # character set, where other bytes can be part of a character.
  defp patient(data_set) do
    case data_set |> text("PatientID") |> to_string() |> String.trim(" ") do
      "" -> {:name, patient_name(data_set)}
      id -> {:id, id}
    end
  end

  # Trailing empty name components may be left out, so "DOE^JOHN^^" is
  # "DOE^JOHN", and "^^" names nobody.
  defp patient_name(data_set) do
    data_set
    |> text("PatientName")
    |> to_string()
    |> String.trim(" ")
    |> String.replace(~r/[\^=]+$/, "")
  end

  defp studies(entries) do
    for {_uid, study} <- grouped(entries, & &1.study) do
      node(record("STUDY", hd(study), @study_keys), series(study))
    end
  end

  defp series(entries) do
    for {_uid, series} <- grouped(entries, & &1.series) do
      node(record("SERIES", hd(series), @series_keys), Enum.map(series, &instance/1))
    end
  end

  defp instance(entry) do
    entry.type
    |> record(entry, instance_keys(entry.type))
    |> Dcmix.put("ReferencedFileID", :CS, entry.file_id)
    |> Dcmix.put("ReferencedSOPClassUIDInFile", :UI, entry.sop_class)
    |> Dcmix.put("ReferencedSOPInstanceUIDInFile", :UI, entry.sop_instance)
    |> Dcmix.put("ReferencedTransferSyntaxUIDInFile", :UI, entry.transfer_syntax)
    |> node([])
  end

  defp grouped(entries, key) do
    groups = Enum.group_by(entries, key)
    entries |> Enum.map(key) |> Enum.uniq() |> Enum.map(&{&1, Map.fetch!(groups, &1)})
  end

  defp node(record, children), do: %{record: record, children: children}

  defp record(type, entry, keys) do
    record =
      Dcmix.new()
      |> Dcmix.put("RecordInUseFlag", :US, 0xFFFF)
      |> Dcmix.put("DirectoryRecordType", :CS, type)
      |> put_character_set(entry.character_set)

    Enum.reduce(keys, record, &put_key(&2, &1, Map.fetch!(entry.values, elem(&1, 0))))
  end

  defp put_character_set(record, nil), do: record

  defp put_character_set(record, character_set),
    do: Dcmix.put(record, "SpecificCharacterSet", :CS, character_set)

  defp put_key(record, {_keyword, _vr, :when_present}, nil), do: record
  defp put_key(record, {keyword, :SQ, _presence}, nil), do: Dcmix.put(record, keyword, :SQ, [])

  # A number can't be written empty, so a required one the instance lacks is
  # left out.
  defp put_key(record, {_keyword, vr, _presence}, nil) when vr in [:US, :UL], do: record

  defp put_key(record, {keyword, vr, _presence}, value),
    do: Dcmix.put(record, keyword, vr, value || "")

  defp encode_file(patients, opts) do
    header =
      Writer.file_meta_header(
        @media_storage_directory,
        Keyword.get_lazy(opts, :file_set_uid, &UID.generate/0),
        @explicit_vr_little_endian,
        implementation_version_name:
          Keyword.get(opts, :implementation_version_name, UID.implementation_version_name())
      )

    file_set_id = Keyword.get(opts, :file_set_id, "")

    first_record_offset =
      byte_size(header) + byte_size(ExplicitVR.encode(root(file_set_id, 0, 0, []))) -
        @sequence_delimiter_bytes

    {patients, _end} = position(patients, first_record_offset)
    root = root(file_set_id, hd(patients).offset, List.last(patients).offset, items(patients))

    header <> ExplicitVR.encode(root)
  end

  defp root(file_set_id, first_offset, last_offset, records) do
    Dcmix.new()
    |> Dcmix.put("FileSetID", :CS, file_set_id)
    |> Dcmix.put("OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity", :UL, first_offset)
    |> Dcmix.put("OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity", :UL, last_offset)
    |> Dcmix.put("FileSetConsistencyFlag", :US, 0)
    |> Dcmix.put("DirectoryRecordSequence", :SQ, records)
  end

  # Depth first: a record, everything under it, then its next sibling. Each
  # node gains `offset`, where its item starts in the file.
  defp position(nodes, offset) do
    Enum.map_reduce(nodes, offset, fn node, offset ->
      {children, next_offset} = position(node.children, offset + item_bytes(node.record))
      {Map.merge(node, %{offset: offset, children: children}), next_offset}
    end)
  end

  defp item_bytes(record),
    do: @item_header_bytes + byte_size(ExplicitVR.encode(linked(record, 0, 0)))

  defp items(nodes) do
    next_offsets = nodes |> Enum.drop(1) |> Enum.map(& &1.offset) |> Enum.concat([0])

    nodes
    |> Enum.zip(next_offsets)
    |> Enum.flat_map(fn {node, next_offset} ->
      [linked(node.record, next_offset, first_offset(node.children)) | items(node.children)]
    end)
  end

  defp first_offset([first | _rest]), do: first.offset
  defp first_offset([]), do: 0

  defp linked(record, next_offset, first_child_offset) do
    record
    |> Dcmix.put("OffsetOfTheNextDirectoryRecord", :UL, next_offset)
    |> Dcmix.put("OffsetOfReferencedLowerLevelDirectoryEntity", :UL, first_child_offset)
  end
end
