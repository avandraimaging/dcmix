defmodule Dcmix.Network.NegotiationTest do
  use ExUnit.Case, async: true

  alias Dcmix.Network.Negotiation

  doctest Dcmix.Network.Negotiation

  @verification "1.2.840.10008.1.1"
  @implicit_vr_le "1.2.840.10008.1.2"
  @explicit_vr_le "1.2.840.10008.1.2.1"
  @big_endian "1.2.840.10008.1.2.2"

  @opts [
    ae_title: "SCP",
    abstract_syntaxes: %{@verification => [@explicit_vr_le, @implicit_vr_le]}
  ]

  describe "negotiate/2" do
    test "accepts a context with our most preferred transfer syntax the requestor proposed" do
      assert {:accept, [context]} =
               Negotiation.negotiate(
                 rq([proposal(1, @verification, [@implicit_vr_le, @explicit_vr_le])]),
                 @opts
               )

      assert context == %{
               id: 1,
               result: 0,
               abstract_syntax: @verification,
               transfer_syntax: @explicit_vr_le
             }
    end

    test "rejects a context whose transfer syntaxes we don't support" do
      assert {:accept, [%{id: 1, result: 4, transfer_syntax: @big_endian}]} =
               Negotiation.negotiate(rq([proposal(1, @verification, [@big_endian])]), @opts)
    end

    test "rejects a context whose abstract syntax we don't support" do
      assert {:accept, [%{id: 1, result: 3}]} =
               Negotiation.negotiate(rq([proposal(1, "1.2.3", [@implicit_vr_le])]), @opts)
    end

    test "rejects a context that proposes no transfer syntax" do
      assert {:accept, [%{id: 1, result: 4, transfer_syntax: ""}]} =
               Negotiation.negotiate(rq([proposal(1, @verification, [])]), @opts)
    end

    test "answers every context, accepted or not, in the order proposed" do
      proposals = [
        proposal(1, "1.2.3", [@implicit_vr_le]),
        proposal(3, @verification, [@implicit_vr_le]),
        proposal(5, @verification, [@big_endian])
      ]

      assert {:accept, contexts} = Negotiation.negotiate(rq(proposals), @opts)
      assert Enum.map(contexts, &{&1.id, &1.result}) == [{1, 3}, {3, 0}, {5, 4}]
    end

    test "accepts an association with no contexts to accept" do
      assert {:accept, []} = Negotiation.negotiate(rq([]), @opts)
    end

    test "rejects a called AE title other than ours, permanently" do
      assert Negotiation.negotiate(rq([], called_ae_title: "OTHER"), @opts) ==
               {:reject, %{result: 1, source: 1, reason: 7}}
    end

    test "ignores trailing spaces in our AE title" do
      assert {:accept, _} = Negotiation.negotiate(rq([]), Keyword.put(@opts, :ae_title, "SCP  "))
    end

    test "treats AE titles as case-sensitive" do
      assert {:reject, %{reason: 7}} =
               Negotiation.negotiate(rq([], called_ae_title: "scp"), @opts)
    end

    test "rejects an application context other than DICOM's, permanently" do
      assert Negotiation.negotiate(rq([], application_context: "1.2.3"), @opts) ==
               {:reject, %{result: 1, source: 1, reason: 2}}
    end
  end

  defp rq(proposals, overrides \\ []) do
    Map.merge(
      %{
        called_ae_title: "SCP",
        calling_ae_title: "SCU",
        application_context: "1.2.840.10008.3.1.1.1",
        presentation_contexts: proposals
      },
      Map.new(overrides)
    )
  end

  defp proposal(id, abstract_syntax, transfer_syntaxes),
    do: %{id: id, abstract_syntax: abstract_syntax, transfer_syntaxes: transfer_syntaxes}
end
