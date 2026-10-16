defmodule Dcmix.Network.NegotiationTest do
  use ExUnit.Case, async: true

  alias Dcmix.Network.{ApplicationContext, Negotiation, SOPClassUID}
  alias Dcmix.Parser.TransferSyntax

  require Dcmix.Network.PDU.AssociateRJ, as: AssociateRJ
  require Dcmix.Network.PDU.PresentationContextResult, as: ContextResult

  doctest Dcmix.Network.Negotiation

  # A SOP Class the SCP doesn't support
  @unsupported_sop_class "1.2.3"

  describe "negotiate/2" do
    test "accepts a context with our most preferred transfer syntax the requestor proposed" do
      proposed = [
        TransferSyntax.implicit_vr_little_endian(),
        TransferSyntax.explicit_vr_little_endian()
      ]

      assert {:accept, [context]} = negotiate(rq([verification(1, proposed)]))

      assert context == %{
               id: 1,
               result: ContextResult.acceptance(),
               abstract_syntax: SOPClassUID.verification(),
               transfer_syntax: TransferSyntax.explicit_vr_little_endian()
             }
    end

    test "rejects a context whose transfer syntaxes we don't support" do
      big_endian = TransferSyntax.explicit_vr_big_endian()

      assert {:accept, [context]} = negotiate(rq([verification(1, [big_endian])]))
      assert context.result == ContextResult.transfer_syntaxes_not_supported()
      assert context.transfer_syntax == big_endian
    end

    test "rejects a context whose abstract syntax we don't support" do
      proposal = proposal(1, @unsupported_sop_class, [TransferSyntax.implicit_vr_little_endian()])

      assert {:accept, [context]} = negotiate(rq([proposal]))
      assert context.result == ContextResult.abstract_syntax_not_supported()
    end

    test "rejects a context that proposes no transfer syntax" do
      assert {:accept, [context]} = negotiate(rq([verification(1, [])]))
      assert context.result == ContextResult.transfer_syntaxes_not_supported()
      assert context.transfer_syntax == ""
    end

    test "answers every context, accepted or not, in the order proposed" do
      implicit = TransferSyntax.implicit_vr_little_endian()

      proposals = [
        proposal(1, @unsupported_sop_class, [implicit]),
        verification(3, [implicit]),
        verification(5, [TransferSyntax.explicit_vr_big_endian()])
      ]

      assert {:accept, contexts} = negotiate(rq(proposals))

      assert Enum.map(contexts, &{&1.id, &1.result}) == [
               {1, ContextResult.abstract_syntax_not_supported()},
               {3, ContextResult.acceptance()},
               {5, ContextResult.transfer_syntaxes_not_supported()}
             ]
    end

    test "accepts an association with no contexts to accept" do
      assert {:accept, []} = negotiate(rq([]))
    end

    test "rejects a called AE title other than ours, permanently" do
      assert {:reject, rejection} = negotiate(rq([], called_ae_title: "OTHER"))

      assert rejection == %{
               result: AssociateRJ.rejected_permanent(),
               source: AssociateRJ.source_service_user(),
               reason: AssociateRJ.service_user_called_ae_title_not_recognized()
             }
    end

    test "ignores trailing spaces in our AE title" do
      assert {:accept, _} = negotiate(rq([]), ae_title: "SCP  ")
    end

    test "treats AE titles as case-sensitive" do
      assert {:reject, rejection} = negotiate(rq([], called_ae_title: "scp"))
      assert rejection.reason == AssociateRJ.service_user_called_ae_title_not_recognized()
    end

    test "rejects an application context other than DICOM's, permanently" do
      assert {:reject, rejection} = negotiate(rq([], application_context: "1.2.3"))

      assert rejection == %{
               result: AssociateRJ.rejected_permanent(),
               source: AssociateRJ.source_service_user(),
               reason: AssociateRJ.service_user_application_context_name_not_supported()
             }
    end
  end

  # Negotiates as an SCP called "SCP" that supports Verification with
  # Explicit, then Implicit VR Little Endian
  defp negotiate(rq, opts \\ []) do
    Negotiation.negotiate(
      rq,
      Keyword.merge(
        [
          ae_title: "SCP",
          abstract_syntaxes: %{
            SOPClassUID.verification() => [
              TransferSyntax.explicit_vr_little_endian(),
              TransferSyntax.implicit_vr_little_endian()
            ]
          }
        ],
        opts
      )
    )
  end

  defp rq(proposals, overrides \\ []) do
    Map.merge(
      %{
        called_ae_title: "SCP",
        calling_ae_title: "SCU",
        application_context: ApplicationContext.dicom(),
        presentation_contexts: proposals
      },
      Map.new(overrides)
    )
  end

  defp verification(id, transfer_syntaxes),
    do: proposal(id, SOPClassUID.verification(), transfer_syntaxes)

  defp proposal(id, abstract_syntax, transfer_syntaxes),
    do: %{id: id, abstract_syntax: abstract_syntax, transfer_syntaxes: transfer_syntaxes}
end
