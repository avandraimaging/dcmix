defmodule Dcmix.Parser.DefinedLengthTest do
  use ExUnit.Case, async: true

  alias Dcmix.{DataElement, DataSet}
  alias Dcmix.Parser.{ExplicitVR, ImplicitVR}

  @anatomic_region_sequence {0x0008, 0x2218}
  @modifier_sequence {0x0008, 0x2220}
  @code_value {0x0008, 0x0100}
  @study_description {0x0008, 0x1030}

  # Explicit VR, hand-built: Dcmix's writers don't write defined-length
  # sequences.
  defp short({g, e}, vr, value, endian) do
    tag(g, e, endian) <> vr <> uint(byte_size(value), 16, endian) <> value
  end

  defp sequence({g, e}, items, endian) do
    tag(g, e, endian) <> "SQ" <> <<0::16>> <> uint(byte_size(items), 32, endian) <> items
  end

  defp defined_item(body, endian),
    do: tag(0xFFFE, 0xE000, endian) <> uint(byte_size(body), 32, endian) <> body

  defp undefined_item(body, endian) do
    tag(0xFFFE, 0xE000, endian) <>
      uint(0xFFFFFFFF, 32, endian) <> body <> tag(0xFFFE, 0xE00D, endian) <> <<0::32>>
  end

  defp tag(g, e, endian), do: uint(g, 16, endian) <> uint(e, 16, endian)

  defp uint(n, size, :little), do: <<n::size(size)-little>>
  defp uint(n, size, :big), do: <<n::size(size)-big>>

  defp parse(data, :little), do: ExplicitVR.parse(data)
  defp parse(data, :big), do: ExplicitVR.parse(data, big_endian: true)

  defp items(ds, tag), do: DataSet.get(ds, tag).value

  describe "ExplicitVR.parse/2" do
    for endian <- [:little, :big] do
      @endian endian

      test "reads a defined-length sequence's items, #{endian} endian" do
        code = short(@code_value, "SH", "T-D4000 ", @endian)

        data =
          sequence(@anatomic_region_sequence, defined_item(code, @endian), @endian) <>
            short(@study_description, "LO", "CT CHEST", @endian)

        {:ok, ds, <<>>} = parse(data, @endian)

        assert %DataElement{vr: :SQ, value: [item]} = DataSet.get(ds, @anatomic_region_sequence)
        assert DataSet.get(item, @code_value).value == "T-D4000"
        assert DataSet.get(ds, @study_description).value == "CT CHEST"
      end

      test "reads defined- and undefined-length items in a defined-length sequence, #{endian} endian" do
        first = short(@code_value, "SH", "A ", @endian)
        second = short(@code_value, "SH", "B ", @endian)

        data =
          sequence(
            @anatomic_region_sequence,
            defined_item(first, @endian) <> undefined_item(second, @endian),
            @endian
          )

        {:ok, ds, <<>>} = parse(data, @endian)

        assert [a, b] = items(ds, @anatomic_region_sequence)
        assert DataSet.get(a, @code_value).value == "A"
        assert DataSet.get(b, @code_value).value == "B"
      end

      test "reads a defined-length sequence nested in a defined-length item, #{endian} endian" do
        modifier =
          sequence(
            @modifier_sequence,
            defined_item(short(@code_value, "SH", "LEFT", @endian), @endian),
            @endian
          )

        item = short(@code_value, "SH", "LUNG", @endian) <> modifier
        data = sequence(@anatomic_region_sequence, defined_item(item, @endian), @endian)

        {:ok, ds, <<>>} = parse(data, @endian)

        assert [region] = items(ds, @anatomic_region_sequence)
        assert DataSet.get(region, @code_value).value == "LUNG"
        assert [modifier_item] = items(region, @modifier_sequence)
        assert DataSet.get(modifier_item, @code_value).value == "LEFT"
      end

      test "reads an empty defined-length sequence as no items, #{endian} endian" do
        data =
          sequence(@anatomic_region_sequence, <<>>, @endian) <>
            short(@study_description, "LO", "CT CHEST", @endian)

        {:ok, ds, <<>>} = parse(data, @endian)

        assert %DataElement{vr: :SQ, value: []} = DataSet.get(ds, @anatomic_region_sequence)
        assert DataSet.get(ds, @study_description).value == "CT CHEST"
      end

      test "skips delimiters and zero padding some encoders write in a defined-length sequence, #{endian} endian" do
        item = defined_item(short(@code_value, "SH", "LUNG", @endian), @endian)
        delimiter = fn e -> tag(0xFFFE, e, @endian) <> <<0::32>> end

        for bytes <- [
              item <> delimiter.(0xE00D),
              item <> delimiter.(0xE0DD),
              item <> <<0, 0>>,
              item <> <<0::64>>,
              item <> <<0::120>>
            ] do
          data =
            sequence(@anatomic_region_sequence, bytes, @endian) <>
              short(@study_description, "LO", "CT CHEST", @endian)

          {:ok, ds, <<>>} = parse(data, @endian)

          assert [region] = items(ds, @anatomic_region_sequence)
          assert DataSet.get(region, @code_value).value == "LUNG"
          assert DataSet.get(ds, @study_description).value == "CT CHEST"
        end
      end

      test "reads each item between delimiters in a defined-length sequence, #{endian} endian" do
        item = fn code -> defined_item(short(@code_value, "SH", code, @endian), @endian) end
        delimiter = fn e -> tag(0xFFFE, e, @endian) <> <<0::32>> end

        bytes =
          item.("A ") <>
            delimiter.(0xE00D) <> item.("B ") <> delimiter.(0xE00D) <> delimiter.(0xE0DD)

        {:ok, ds, <<>>} = parse(sequence(@anatomic_region_sequence, bytes, @endian), @endian)

        assert [a, b] = items(ds, @anatomic_region_sequence)
        assert DataSet.get(a, @code_value).value == "A"
        assert DataSet.get(b, @code_value).value == "B"
      end
    end

    test "keeps a defined-length sequence it can't read as UN, with its bytes" do
      # Not an item; an item longer than the sequence; an item whose element
      # runs past its end; an item followed by bytes that aren't zero padding
      truncated = tag(0x0008, 0x0100, :big) <> "SH" <> uint(10, 16, :big) <> "AB"

      for {bytes, endian} <- [
            {<<1, 2, 3, 4>>, :little},
            {tag(0xFFFE, 0xE000, :little) <> uint(100, 32, :little), :little},
            {defined_item(truncated, :big), :big},
            {defined_item(short(@code_value, "SH", "LUNG", :little), :little) <> <<1, 2>>,
             :little}
          ] do
        data =
          sequence(@anatomic_region_sequence, bytes, endian) <>
            short(@study_description, "LO", "CT CHEST", endian)

        {:ok, ds, <<>>} = parse(data, endian)

        assert %DataElement{vr: :UN, value: ^bytes} = DataSet.get(ds, @anatomic_region_sequence)
        assert DataSet.get(ds, @study_description).value == "CT CHEST"
      end
    end

    test "reads a defined-length sequence nested in an undefined-length item" do
      modifier =
        sequence(
          @modifier_sequence,
          defined_item(short(@code_value, "SH", "LEFT", :little), :little),
          :little
        )

      data =
        tag(0x0008, 0x2218, :little) <>
          "SQ" <>
          <<0::16, 0xFFFFFFFF::32-little>> <>
          undefined_item(modifier, :little) <>
          tag(0xFFFE, 0xE0DD, :little) <> <<0::32>>

      {:ok, ds, <<>>} = ExplicitVR.parse(data)

      assert [region] = items(ds, @anatomic_region_sequence)
      assert [modifier_item] = items(region, @modifier_sequence)
      assert DataSet.get(modifier_item, @code_value).value == "LEFT"
    end
  end

  describe "ImplicitVR.parse/2" do
    test "reads a defined-length sequence nested in a defined-length item" do
      element = fn {g, e}, v ->
        <<g::16-little, e::16-little, byte_size(v)::32-little, v::binary>>
      end

      item = fn body -> defined_item(body, :little) end

      modifier = element.(@modifier_sequence, item.(element.(@code_value, "LEFT")))
      data = element.(@anatomic_region_sequence, item.(element.(@code_value, "LUNG") <> modifier))

      {:ok, ds, <<>>} = ImplicitVR.parse(data)

      assert [region] = items(ds, @anatomic_region_sequence)
      assert DataSet.get(region, @code_value).value == "LUNG"
      assert [modifier_item] = items(region, @modifier_sequence)
      assert DataSet.get(modifier_item, @code_value).value == "LEFT"
    end

    test "skips delimiters and zero padding some encoders write in a defined-length sequence" do
      element = fn {g, e}, v ->
        <<g::16-little, e::16-little, byte_size(v)::32-little, v::binary>>
      end

      item = defined_item(element.(@code_value, "LUNG"), :little)
      delimiter = fn e -> tag(0xFFFE, e, :little) <> <<0::32>> end

      for bytes <- [
            item <> delimiter.(0xE00D),
            item <> delimiter.(0xE0DD),
            item <> <<0, 0>>,
            item <> <<0::64>>
          ] do
        {:ok, ds, <<>>} = ImplicitVR.parse(element.(@anatomic_region_sequence, bytes))

        assert [region] = items(ds, @anatomic_region_sequence)
        assert DataSet.get(region, @code_value).value == "LUNG"
      end
    end
  end
end
