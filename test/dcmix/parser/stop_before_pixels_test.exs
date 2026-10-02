defmodule Dcmix.Parser.StopBeforePixelsTest do
  use ExUnit.Case, async: true

  alias Dcmix.{DataSet, Tag, Writer}

  @fixtures_path "test/fixtures"
  @pixel_data {0x7FE0, 0x0010}

  defp elements_before_pixels(dataset) do
    dataset
    |> DataSet.to_list()
    |> Enum.filter(&(Tag.compare(&1.tag, {0x7FE0, 0x0008}) == :lt))
  end

  defp dataset_with_pixels(pixel_bytes) do
    DataSet.new()
    |> DataSet.put_element({0x0008, 0x0016}, :UI, "1.2.840.10008.5.1.4.1.1.2")
    |> DataSet.put_element({0x0008, 0x0018}, :UI, "1.2.3.4.5.6.7.8.9")
    |> DataSet.put_element({0x0010, 0x0010}, :PN, "Test^Patient")
    |> DataSet.put_element({0x0028, 0x0010}, :US, 1)
    |> DataSet.put_element(@pixel_data, :OW, pixel_bytes)
  end

  describe "read_file/2 with stop_before_pixels" do
    for {fixture, encoding} <- [
          {"nema_mr_knee_512x512.dcm", "explicit VR"},
          {"nema_mr_cardiac_256x256.dcm", "implicit VR"}
        ] do
      test "reads every element before the pixel data of an #{encoding} file" do
        file = Path.join(@fixtures_path, unquote(fixture))

        {:ok, full} = Dcmix.read_file(file)
        assert {:ok, header} = Dcmix.read_file(file, stop_before_pixels: true)

        refute DataSet.has_tag?(header, @pixel_data)
        assert DataSet.to_list(header) == elements_before_pixels(full)
      end
    end

    test "keeps reading while the header is larger than the initial read" do
      file = Path.join(@fixtures_path, "nema_mr_knee_512x512.dcm")

      {:ok, full} = Dcmix.read_file(file)
      assert {:ok, header} = Dcmix.read_file(file, stop_before_pixels: true, read_size: 200)

      assert DataSet.to_list(header) == elements_before_pixels(full)
    end

    @tag :tmp_dir
    test "never parses the pixel data, so a truncated pixel value does not matter", %{
      tmp_dir: tmp_dir
    } do
      {:ok, binary} = Writer.encode(dataset_with_pixels(:binary.copy(<<0>>, 100_000)))
      truncated = binary_part(binary, 0, byte_size(binary) - 50_000)
      path = Path.join(tmp_dir, "truncated.dcm")
      File.write!(path, truncated)

      assert {:error, _} = Dcmix.read_file(path)

      assert {:ok, header} = Dcmix.read_file(path, stop_before_pixels: true, read_size: 200)
      assert DataSet.get_value(header, {0x0010, 0x0010}) == "Test^Patient"
      refute DataSet.has_tag?(header, @pixel_data)
    end

    @tag :tmp_dir
    test "reads the whole file when it has no pixel data", %{tmp_dir: tmp_dir} do
      dataset = DataSet.delete(dataset_with_pixels(<<>>), @pixel_data)
      path = Path.join(tmp_dir, "no_pixels.dcm")
      :ok = Writer.write_file(dataset, path)

      {:ok, full} = Dcmix.read_file(path)
      assert {:ok, header} = Dcmix.read_file(path, stop_before_pixels: true, read_size: 200)

      assert DataSet.to_list(header) == DataSet.to_list(full)
    end

    test "returns a file error for a missing file" do
      assert {:error, {:file_error, :enoent}} =
               Dcmix.read_file("nonexistent.dcm", stop_before_pixels: true)
    end
  end

  describe "parse/2 with stop_before_pixels" do
    test "omits the pixel data from an in-memory file" do
      {:ok, binary} = Writer.encode(dataset_with_pixels(:binary.copy(<<1, 2>>, 512)))

      assert {:ok, header} = Dcmix.Parser.parse(binary, stop_before_pixels: true)

      assert DataSet.get_value(header, {0x0010, 0x0010}) == "Test^Patient"
      refute DataSet.has_tag?(header, @pixel_data)
    end
  end
end
