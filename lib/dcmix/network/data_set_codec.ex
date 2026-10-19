defmodule Dcmix.Network.DataSetCodec do
  @moduledoc """
  Encodes and decodes the data set of a DIMSE message (a query identifier,
  a match, a response identifier) in the transfer syntax its presentation
  context accepted.
  """

  alias Dcmix.DataSet
  alias Dcmix.Parser.{ExplicitVR, ImplicitVR, TransferSyntax}
  alias Dcmix.Writer

  @doc """
  Encodes `dataset` in the given transfer syntax.
  """
  @spec encode(DataSet.t(), String.t()) :: binary()
  def encode(%DataSet{} = dataset, transfer_syntax_uid) do
    {:ok, ts} = TransferSyntax.lookup(transfer_syntax_uid)

    if ts.explicit_vr,
      do: Writer.ExplicitVR.encode(dataset, big_endian: ts.big_endian),
      else: Writer.ImplicitVR.encode(dataset)
  end

  @doc """
  Decodes a data set encoded in the given transfer syntax.
  """
  @spec decode(binary(), String.t()) :: {:ok, DataSet.t()} | {:error, term()}
  def decode(bytes, transfer_syntax_uid) do
    {:ok, ts} = TransferSyntax.lookup(transfer_syntax_uid)

    result =
      if ts.explicit_vr,
        do: ExplicitVR.parse(bytes, big_endian: ts.big_endian),
        else: ImplicitVR.parse(bytes)

    case result do
      {:ok, dataset, _rest} -> {:ok, dataset}
      {:error, _} = error -> error
    end
  end
end
