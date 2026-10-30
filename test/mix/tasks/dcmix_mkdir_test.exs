defmodule Mix.Tasks.Dcmix.MkdirTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Dcmix.Mkdir

  @moduletag :tmp_dir

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    test "writes the DICOMDIR at the top of the directory, with each file's path as its File ID",
         %{tmp_dir: dir} do
      write_instance(dir, ~w(DICOM ST000000 SE000000 IN000000))
      write_instance(dir, ~w(DICOM ST000000 SE000000 IN000001))

      Mkdir.run(["--fileset-id", "STUDY_01", dir])

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "referring to 2 instance(s)"

      {:ok, dicomdir} = Dcmix.read_file(Path.join(dir, "DICOMDIR"))
      assert Dcmix.get_string(dicomdir, "FileSetID") =~ "STUDY_01"

      assert file_ids(dicomdir) == [
               "DICOM\\ST000000\\SE000000\\IN000000",
               "DICOM\\ST000000\\SE000000\\IN000001"
             ]
    end

    test "names each file it leaves out, and why", %{tmp_dir: dir} do
      write_instance(dir, ~w(DICOM IN000000))
      write_instance(dir, ~w(DICOM in000001))
      write_instance(dir, ~w(DICOM IN000002), study: :absent)
      File.write!(Path.join([dir, "DICOM", "NOTES"]), "not a dicom file")

      Mkdir.run([dir])

      assert errors(dir) == [
               "DICOM/IN000002: it lacks a UID its record needs",
               "DICOM/NOTES: it doesn't parse as DICOM",
               "DICOM/in000001: its path isn't a valid File ID"
             ]

      {:ok, dicomdir} = Dcmix.read_file(Path.join(dir, "DICOMDIR"))
      assert file_ids(dicomdir) == ["DICOM\\IN000000"]
    end

    test "leaves out a path deeper than eight components", %{tmp_dir: dir} do
      write_instance(dir, ~w(A B C D E F G H I))
      write_instance(dir, ~w(IN000000))

      Mkdir.run([dir])

      assert errors(dir) == ["A/B/C/D/E/F/G/H/I: its path isn't a valid File ID"]
    end

    test "replaces a DICOMDIR already there rather than reading it as an instance",
         %{tmp_dir: dir} do
      write_instance(dir, ~w(IN000000))
      Mkdir.run([dir])
      Mkdir.run([dir])

      assert errors(dir) == []
      {:ok, dicomdir} = Dcmix.read_file(Path.join(dir, "DICOMDIR"))
      assert file_ids(dicomdir) == ["IN000000"]
    end

    test "fails when nothing can go in a DICOMDIR", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "NOTES"), "not a dicom file")

      assert catch_exit(Mkdir.run([dir])) == {:shutdown, 1}

      assert errors(dir) == [
               "NOTES: it doesn't parse as DICOM",
               "Nothing under can go in a DICOMDIR"
             ]

      refute File.exists?(Path.join(dir, "DICOMDIR"))
    end

    test "names the files encode refused when it refuses them all", %{tmp_dir: dir} do
      write_instance(dir, ~w(IN000000), study: :absent)

      assert catch_exit(Mkdir.run([dir])) == {:shutdown, 1}

      assert errors(dir) == [
               "IN000000: it lacks a UID its record needs",
               "Nothing under can go in a DICOMDIR"
             ]
    end

    test "fails on a File-set ID that isn't a valid CS value", %{tmp_dir: dir} do
      write_instance(dir, ~w(IN000000))

      assert catch_exit(Mkdir.run(["--fileset-id", "study-1", dir])) == {:shutdown, 1}
      assert errors(dir) == ["Not a valid File-set ID: study-1"]
      refute File.exists?(Path.join(dir, "DICOMDIR"))
    end

    test "fails without a directory", %{tmp_dir: dir} do
      assert catch_exit(Mkdir.run([])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, [usage]}
      assert usage =~ "Usage:"

      assert catch_exit(Mkdir.run([Path.join(dir, "missing")])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, [missing]}
      assert missing =~ "Not a directory"
    end
  end

  # A Part 10 instance at `file_id` under `dir`. `study: :absent` leaves out
  # its Study Instance UID.
  defp write_instance(dir, file_id, opts \\ []) do
    path = Path.join([dir | file_id])
    File.mkdir_p!(Path.dirname(path))

    data_set =
      Dcmix.new()
      |> Dcmix.put("SOPClassUID", :UI, "1.2.840.10008.5.1.4.1.1.7")
      |> Dcmix.put("SOPInstanceUID", :UI, "1.2.9." <> Integer.to_string(:erlang.phash2(file_id)))
      |> Dcmix.put("PatientID", :LO, "FIXTURE-1")
      |> Dcmix.put("SeriesInstanceUID", :UI, "1.2.9.1.1")
      |> Dcmix.put("Modality", :CS, "OT")

    data_set =
      if opts[:study] == :absent,
        do: data_set,
        else: Dcmix.put(data_set, "StudyInstanceUID", :UI, "1.2.9.1")

    :ok = Dcmix.write_file(data_set, path)
  end

  # The errors the task printed, sorted, with the "Left out" prefix and `dir`
  # taken off each.
  defp errors(dir) do
    Stream.repeatedly(fn ->
      receive do
        {:mix_shell, :error, [message]} -> message
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(&is_binary/1)
    |> Enum.map(&String.replace(&1, ["Left out " <> dir <> "/", dir <> " "], ""))
    |> Enum.sort()
  end

  defp file_ids(dicomdir) do
    dicomdir
    |> Dcmix.get("DirectoryRecordSequence")
    |> Enum.map(&Dcmix.get_string(&1, "ReferencedFileID"))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.trim_trailing(&1, " "))
  end
end
