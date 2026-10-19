defmodule Dcmix.Network.DataSetCodecTest do
  use ExUnit.Case, async: true

  alias Dcmix.DataSet
  alias Dcmix.Network.DataSetCodec
  alias Dcmix.Parser.TransferSyntax

  @data_set DataSet.new()
            |> DataSet.put_element({0x0008, 0x0052}, :CS, "STUDY")
            |> DataSet.put_element({0x0020, 0x000D}, :UI, "1.2.3.4")

  for {name, uid} <- [
        implicit_little: TransferSyntax.implicit_vr_little_endian(),
        explicit_little: TransferSyntax.explicit_vr_little_endian(),
        explicit_big: TransferSyntax.explicit_vr_big_endian()
      ] do
    test "decodes what it encodes in #{name} endian" do
      bytes = DataSetCodec.encode(@data_set, unquote(uid))

      assert {:ok, decoded} = DataSetCodec.decode(bytes, unquote(uid))
      assert DataSet.get_string(decoded, {0x0008, 0x0052}) == "STUDY"
      assert DataSet.get_string(decoded, {0x0020, 0x000D}) == "1.2.3.4"
    end
  end

  test "encodes Implicit VR without VRs and Explicit VR with them" do
    implicit = DataSetCodec.encode(@data_set, TransferSyntax.implicit_vr_little_endian())
    explicit = DataSetCodec.encode(@data_set, TransferSyntax.explicit_vr_little_endian())

    assert :binary.match(explicit, "CS") != :nomatch
    assert :binary.match(implicit, "CS") == :nomatch
  end

  test "returns the parser's error for bytes that don't decode" do
    # An element whose length runs past the end of the data
    truncated = <<0x08, 0x00, 0x52, 0x00, 100::32-little, "AB">>

    assert DataSetCodec.decode(truncated, TransferSyntax.implicit_vr_little_endian()) ==
             {:error, :unexpected_eof}
  end
end
