defmodule Dcmix.Parser.NonFiniteFloatTest do
  use ExUnit.Case, async: true

  alias Dcmix.{DataElement, DataSet}
  alias Dcmix.Parser.{ExplicitVR, ImplicitVR}
  alias Dcmix.Writer

  # Erlang floats have no NaN or infinity.
  @nan_fl <<0x7FC00000::32-little>>
  @infinity_fd <<0x7FF0000000000000::64-little>>
  @negative_infinity_fd <<0xFFF0000000000000::64-little>>

  # RealWorldValueSlope (FD), RecommendedDisplayFrameRateInFloat (FL)
  @slope {0x0040, 0x9225}
  @frame_rate {0x0008, 0x9459}
  @study_description {0x0008, 0x1030}

  describe "ImplicitVR.parse/2" do
    test "keeps an FL or FD value holding NaN or infinity as UN, and writes its bytes back" do
      fd = @infinity_fd <> <<1.5::64-float-little>> <> @negative_infinity_fd

      data =
        <<0x08, 0x00, 0x59, 0x94, 4::32-little>> <>
          @nan_fl <>
          <<0x08, 0x00, 0x30, 0x10, 8::32-little, "CT CHEST">> <>
          <<0x40, 0x00, 0x25, 0x92, 24::32-little>> <> fd

      {:ok, ds, <<>>} = ImplicitVR.parse(data)

      assert %DataElement{vr: :UN, value: @nan_fl} = DataSet.get(ds, @frame_rate)
      assert %DataElement{vr: :UN, value: ^fd} = DataSet.get(ds, @slope)
      assert DataSet.get(ds, @study_description).value == "CT CHEST"
      assert Writer.ImplicitVR.encode(ds) == data
    end
  end

  describe "ExplicitVR.parse/2" do
    test "keeps an FL or FD value holding NaN or infinity as UN, with its bytes" do
      data =
        <<0x08, 0x00, 0x59, 0x94, "FL", 4::16-little>> <>
          @nan_fl <>
          <<0x40, 0x00, 0x25, 0x92, "FD", 8::16-little>> <> @negative_infinity_fd

      {:ok, ds, <<>>} = ExplicitVR.parse(data)

      assert %DataElement{vr: :UN, value: @nan_fl} = DataSet.get(ds, @frame_rate)
      assert %DataElement{vr: :UN, value: @negative_infinity_fd} = DataSet.get(ds, @slope)

      {:ok, rewritten, <<>>} = ds |> Writer.ExplicitVR.encode() |> ExplicitVR.parse()
      assert DataSet.get(rewritten, @slope).value == @negative_infinity_fd
    end

    test "keeps them as UN in big endian data too" do
      data = <<0x0040::16-big, 0x9225::16-big, "FD", 8::16-big, 0x7FF0000000000000::64-big>>

      {:ok, ds, <<>>} = ExplicitVR.parse(data, big_endian: true)

      assert %DataElement{vr: :UN, value: <<0x7FF0000000000000::64-big>>} =
               DataSet.get(ds, @slope)
    end

    test "still reads finite FD values" do
      data = <<0x40, 0x00, 0x25, 0x92, "FD", 8::16-little, -2.5::64-float-little>>

      {:ok, ds, <<>>} = ExplicitVR.parse(data)

      assert %DataElement{vr: :FD, value: -2.5} = DataSet.get(ds, @slope)
    end

    test "reads a big endian FD whose bytes would be NaN read little endian" do
      value = <<0x3FF000000000F07F::64-big>>
      data = <<0x0040::16-big, 0x9225::16-big, "FD", 8::16-big>> <> value
      <<expected::64-float-big>> = value

      {:ok, ds, <<>>} = ExplicitVR.parse(data, big_endian: true)

      assert %DataElement{vr: :FD, value: ^expected} = DataSet.get(ds, @slope)
    end
  end
end
