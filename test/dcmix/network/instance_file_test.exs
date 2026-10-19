defmodule Dcmix.Network.InstanceFileTest do
  use ExUnit.Case, async: true

  alias Dcmix.{DataSet, Tag}
  alias Dcmix.Network.InstanceFile
  alias Dcmix.Parser.TransferSyntax
  alias Dcmix.Writer.ExplicitVR

  require Dcmix.Network.DIMSE.Status, as: Status

  @ct_image_storage "1.2.840.10008.5.1.4.1.1.2"

  setup do
    dir =
      Path.join(System.tmp_dir!(), "dcmix_instance_file_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp instance(uid \\ "1.2.3.4") do
    %{
      sop_class_uid: @ct_image_storage,
      sop_instance_uid: uid,
      transfer_syntax: TransferSyntax.explicit_vr_little_endian()
    }
  end

  defp data_set(patient_id) do
    DataSet.new()
    |> DataSet.put_element({0x0010, 0x0020}, :LO, patient_id)
    |> ExplicitVR.encode(big_endian: false)
  end

  describe "open/3, write/2 and close/1" do
    test "write a Part 10 file of the meta header and the fragments as received", %{dir: dir} do
      <<first::binary-size(4), rest::binary>> = data_set("PID-1")

      assert {:ok, file} = InstanceFile.open(dir, instance(), source_ae_title: "PACS")
      assert :ok = InstanceFile.write(file, first)
      assert :ok = InstanceFile.write(file, rest)
      assert {:ok, path} = InstanceFile.close(file)

      assert path == Path.join(dir, "1.2.3.4")
      assert {:ok, ds} = Dcmix.read_file(path)
      assert DataSet.get_value(ds, Tag.media_storage_sop_class_uid()) == @ct_image_storage
      assert DataSet.get_value(ds, Tag.media_storage_sop_instance_uid()) == "1.2.3.4"
      assert DataSet.get_string(ds, {0x0002, 0x0016}) == "PACS"
      assert DataSet.get_string(ds, {0x0010, 0x0020}) == "PID-1"
    end

    test "leave out Source AE Title unless given", %{dir: dir} do
      {:ok, file} = InstanceFile.open(dir, instance())
      {:ok, path} = InstanceFile.close(file)

      {:ok, ds} = Dcmix.read_file(path)
      refute DataSet.has_tag?(ds, {0x0002, 0x0016})
    end

    test "write to <name>.part until closed", %{dir: dir} do
      {:ok, file} = InstanceFile.open(dir, instance())

      assert File.ls!(dir) == ["1.2.3.4.part"]
      {:ok, _path} = InstanceFile.close(file)
      assert File.ls!(dir) == ["1.2.3.4"]
    end

    test "replace an earlier copy of the instance once complete", %{dir: dir} do
      write_instance(dir, "OLD")
      write_instance(dir, "NEW")

      {:ok, ds} = Dcmix.read_file(Path.join(dir, "1.2.3.4"))
      assert DataSet.get_string(ds, {0x0010, 0x0020}) == "NEW"
    end
  end

  describe "discard/1" do
    test "deletes the .part file and leaves an earlier copy alone", %{dir: dir} do
      write_instance(dir, "OLD")
      {:ok, file} = InstanceFile.open(dir, instance())

      assert InstanceFile.discard(file) == :ok
      assert File.ls!(dir) == ["1.2.3.4"]
      {:ok, ds} = Dcmix.read_file(Path.join(dir, "1.2.3.4"))
      assert DataSet.get_string(ds, {0x0010, 0x0020}) == "OLD"
    end
  end

  describe "file names" do
    test "sanitize the SOP Instance UID", %{dir: dir} do
      {:ok, file} = InstanceFile.open(dir, instance(" 1.2/3:4 5\\6" <> <<0>>))
      {:ok, path} = InstanceFile.close(file)

      assert Path.basename(path) == "1.2_3_4_5_6"
    end

    test "refuse a UID that can't name a file, as Cannot Understand", %{dir: dir} do
      for uid <- [nil, "", "  ", ".", "..", "1.2.", "CON", "com1.2", "Lpt9"] do
        assert InstanceFile.open(dir, instance(uid)) == {:error, Status.cannot_understand()},
               "expected #{inspect(uid)} to be refused"
      end

      assert File.ls!(dir) == []
    end

    test "allow names that only start like a reserved device", %{dir: dir} do
      for uid <- ["COM10.1", "CONSOLE"] do
        assert {:ok, file} = InstanceFile.open(dir, instance(uid))
        InstanceFile.discard(file)
      end
    end
  end

  describe "failures" do
    test "open/3 answers Out of Resources when the file can't be created", %{dir: dir} do
      missing = Path.join(dir, "missing")
      assert InstanceFile.open(missing, instance()) == {:error, Status.out_of_resources()}
    end

    test "write/2 answers Out of Resources and deletes the .part file", %{dir: dir} do
      {:ok, file} = InstanceFile.open(dir, instance())
      :ok = File.close(file.io)

      assert InstanceFile.write(file, "data") == {:error, Status.out_of_resources()}
      assert File.ls!(dir) == []
    end

    test "close/1 answers Out of Resources and deletes the .part file", %{dir: dir} do
      # A directory in the way of the final name makes the rename fail
      File.mkdir_p!(Path.join(dir, "1.2.3.4/x"))
      {:ok, file} = InstanceFile.open(dir, instance())

      assert InstanceFile.close(file) == {:error, Status.out_of_resources()}
      assert File.ls!(dir) == ["1.2.3.4"]
    end
  end

  defp write_instance(dir, patient_id) do
    {:ok, file} = InstanceFile.open(dir, instance())
    :ok = InstanceFile.write(file, data_set(patient_id))
    {:ok, _path} = InstanceFile.close(file)
  end
end
