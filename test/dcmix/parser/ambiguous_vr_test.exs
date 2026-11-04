defmodule Dcmix.Parser.AmbiguousVRTest do
  use ExUnit.Case, async: true

  alias Dcmix.{DataElement, DataSet}
  alias Dcmix.Parser.{ExplicitVR, ImplicitVR}
  alias Dcmix.Writer

  @pixel_representation {0x0028, 0x0103}
  @smallest_pixel_value {0x0028, 0x0106}
  @pixel_padding_value {0x0028, 0x0120}
  @voi_lut_sequence {0x0028, 0x3010}
  @lut_descriptor {0x0028, 0x3002}
  @lut_data {0x0028, 0x3006}
  @real_world_value_mapping_sequence {0x0040, 0x9096}
  @first_value_mapped {0x0040, 0x9216}

  defp implicit(elements) do
    {:ok, parsed, <<>>} =
      elements |> DataSet.new() |> Writer.ImplicitVR.encode() |> ImplicitVR.parse()

    parsed
  end

  defp items(ds, tag), do: DataSet.get(ds, tag).value

  describe "ImplicitVR.parse/2" do
    test "reads US or SS values as SS when PixelRepresentation is 1" do
      ds =
        implicit([
          DataElement.new(@pixel_representation, :US, 1),
          DataElement.new(@smallest_pixel_value, :SS, -1024),
          DataElement.new(@pixel_padding_value, :SS, -2000)
        ])

      assert %DataElement{vr: :SS, value: -1024} = DataSet.get(ds, @smallest_pixel_value)
      assert %DataElement{vr: :SS, value: -2000} = DataSet.get(ds, @pixel_padding_value)
    end

    test "reads them as US when PixelRepresentation is 0" do
      ds =
        implicit([
          DataElement.new(@pixel_representation, :US, 0),
          DataElement.new(@smallest_pixel_value, :US, 40_000)
        ])

      assert %DataElement{vr: :US, value: 40_000} = DataSet.get(ds, @smallest_pixel_value)
    end

    test "reads them as US when nothing decides" do
      ds = implicit([DataElement.new(@smallest_pixel_value, :SS, -1024)])

      assert %DataElement{vr: :US, value: 64_512} = DataSet.get(ds, @smallest_pixel_value)
    end

    test "takes PixelRepresentation from an enclosing data set inside a sequence" do
      mapping = DataSet.new([DataElement.new(@first_value_mapped, :SS, -100)])

      ds =
        implicit([
          DataElement.new(@pixel_representation, :US, 1),
          DataElement.new(@real_world_value_mapping_sequence, :SQ, [mapping])
        ])

      assert [item] = items(ds, @real_world_value_mapping_sequence)
      assert %DataElement{vr: :SS, value: -100} = DataSet.get(item, @first_value_mapped)
    end

    test "takes the nearest PixelRepresentation, and leaves the enclosing one as it was" do
      mapping =
        DataSet.new([
          DataElement.new(@pixel_representation, :US, 0),
          DataElement.new(@first_value_mapped, :US, 40_000)
        ])

      ds =
        implicit([
          DataElement.new(@pixel_representation, :US, 1),
          DataElement.new(@real_world_value_mapping_sequence, :SQ, [mapping]),
          DataElement.new(@pixel_padding_value, :SS, -2000)
        ])

      assert [item] = items(ds, @real_world_value_mapping_sequence)
      assert %DataElement{vr: :US, value: 40_000} = DataSet.get(item, @first_value_mapped)
      assert %DataElement{vr: :SS, value: -2000} = DataSet.get(ds, @pixel_padding_value)
    end

    test "decides each item of a sequence from its own data set, not its sibling's" do
      # Hand-built: a defined-length sequence of defined- and undefined-length
      # items, which Writer.ImplicitVR doesn't write
      element = fn {g, e}, v ->
        <<g::16-little, e::16-little, byte_size(v)::32-little, v::binary>>
      end

      defined = fn body ->
        <<0xFFFE::16-little, 0xE000::16-little, byte_size(body)::32-little, body::binary>>
      end

      undefined = fn body ->
        <<0xFFFE::16-little, 0xE000::16-little, 0xFFFFFFFF::32-little, body::binary,
          0xFFFE::16-little, 0xE00D::16-little, 0::32>>
      end

      pixel_representation = fn n -> element.(@pixel_representation, <<n::16-little>>) end
      first_value_mapped = element.(@first_value_mapped, <<-100::16-signed-little>>)

      for item <- [defined, undefined] do
        items = item.(pixel_representation.(0) <> first_value_mapped) <> item.(first_value_mapped)

        data =
          pixel_representation.(1) <>
            element.(@real_world_value_mapping_sequence, items) <>
            element.(@pixel_padding_value, <<-2000::16-signed-little>>)

        {:ok, ds, <<>>} = ImplicitVR.parse(data)

        assert [first, second] = items(ds, @real_world_value_mapping_sequence)
        assert %DataElement{vr: :US, value: 65_436} = DataSet.get(first, @first_value_mapped)
        assert %DataElement{vr: :SS, value: -100} = DataSet.get(second, @first_value_mapped)
        assert %DataElement{vr: :SS, value: -2000} = DataSet.get(ds, @pixel_padding_value)
      end
    end

    test "reads a signed LUT descriptor's first and third values unsigned" do
      lut = DataSet.new([DataElement.new(@lut_descriptor, :SS, [40_000, -1000, 16])])

      ds =
        implicit([
          DataElement.new(@pixel_representation, :US, 1),
          DataElement.new(@voi_lut_sequence, :SQ, [lut])
        ])

      assert [item] = items(ds, @voi_lut_sequence)

      assert %DataElement{vr: :SS, value: [40_000, -1000, 16]} =
               DataSet.get(item, @lut_descriptor)
    end

    test "reads LUTData as OW, or as US when its descriptor gives one entry" do
      table = <<1::16-little, 2::16-little, 3::16-little, 4::16-little>>

      many =
        DataSet.new([
          DataElement.new(@lut_descriptor, :US, [4, 0, 12]),
          DataElement.new(@lut_data, :OW, table)
        ])

      one =
        DataSet.new([
          DataElement.new(@lut_descriptor, :US, [1, 0, 12]),
          DataElement.new(@lut_data, :US, 7)
        ])

      ds = implicit([DataElement.new(@voi_lut_sequence, :SQ, [many, one])])

      assert [many_item, one_item] = items(ds, @voi_lut_sequence)
      assert %DataElement{vr: :OW, value: ^table} = DataSet.get(many_item, @lut_data)
      assert %DataElement{vr: :US, value: 7} = DataSet.get(one_item, @lut_data)
    end

    test "reads LUTData by its own item's descriptor, not an enclosing one" do
      lut = DataSet.new([DataElement.new(@lut_data, :US, 7)])

      ds =
        implicit([
          DataElement.new(@lut_descriptor, :US, [4, 0, 12]),
          DataElement.new(@voi_lut_sequence, :SQ, [lut])
        ])

      assert [item] = items(ds, @voi_lut_sequence)
      assert %DataElement{vr: :US, value: 7} = DataSet.get(item, @lut_data)
    end

    test "reads PixelData as OW" do
      ds = implicit([DataElement.new({0x7FE0, 0x0010}, :OW, <<1, 0, 2, 0>>)])

      assert %DataElement{vr: :OW, value: <<1, 0, 2, 0>>} = DataSet.get(ds, {0x7FE0, 0x0010})
    end

    test "keeps a numeric value whose length isn't whole values as UN, with its bytes" do
      # SmallestImagePixelValue, 3 bytes
      data = <<0x28, 0x00, 0x06, 0x01, 3::32-little, 1, 2, 3>>

      {:ok, ds, <<>>} = ImplicitVR.parse(data)

      assert %DataElement{vr: :UN, value: <<1, 2, 3>>} = DataSet.get(ds, @smallest_pixel_value)
    end

    test "keeps a defined-length sequence whose bytes aren't items as UN, with its bytes" do
      # ReferencedPerformedProcedureStepSequence, 4 bytes that aren't an item
      data = <<0x08, 0x00, 0x15, 0x11, 4::32-little, 1, 2, 3, 4>>

      {:ok, ds, <<>>} = ImplicitVR.parse(data)

      assert %DataElement{vr: :UN, value: <<1, 2, 3, 4>>} = DataSet.get(ds, {0x0008, 0x1115})
    end
  end

  describe "ExplicitVR.parse/2" do
    test "reads a signed LUT descriptor's first and third values unsigned" do
      binary =
        [DataElement.new(@lut_descriptor, :SS, [40_000, -1000, 16])]
        |> DataSet.new()
        |> Writer.ExplicitVR.encode()

      {:ok, ds, <<>>} = ExplicitVR.parse(binary)

      assert %DataElement{vr: :SS, value: [40_000, -1000, 16]} = DataSet.get(ds, @lut_descriptor)
    end

    test "keeps a numeric value whose length isn't whole values as UN, with its bytes" do
      data = <<0x28, 0x00, 0x06, 0x01, "US", 3::16-little, 1, 2, 3>>

      {:ok, ds, <<>>} = ExplicitVR.parse(data)

      assert %DataElement{vr: :UN, value: <<1, 2, 3>>} = DataSet.get(ds, @smallest_pixel_value)
    end
  end
end
