defmodule Dcmix.Network.Negotiation do
  @moduledoc """
  Decides how an SCP answers an A-ASSOCIATE-RQ (PS3.8 9.3, PS3.7 D.3.3).

  The association is rejected outright when the requestor asks for an
  application context other than DICOM's, or calls an AE title other than
  ours. Otherwise it is accepted, and each proposed presentation context is
  accepted or rejected on its own:

  - its abstract syntax must be one we support, or it is rejected with
    result 3 (abstract-syntax-not-supported);
  - one of its transfer syntaxes must be one we support for that abstract
    syntax, or it is rejected with result 4 (transfer-syntaxes-not-supported).

  An accepted context gets the first of our transfer syntaxes, in our order
  of preference, that the requestor proposed.

  ## Example

      iex> rq = %{
      ...>   called_ae_title: "STORE_SCP",
      ...>   application_context: "1.2.840.10008.3.1.1.1",
      ...>   presentation_contexts: [
      ...>     %{id: 1, abstract_syntax: "1.2.840.10008.1.1", transfer_syntaxes: ["1.2.840.10008.1.2"]},
      ...>     %{id: 3, abstract_syntax: "1.2.3", transfer_syntaxes: ["1.2.840.10008.1.2"]}
      ...>   ]
      ...> }
      iex> Dcmix.Network.Negotiation.negotiate(rq,
      ...>   ae_title: "STORE_SCP",
      ...>   abstract_syntaxes: %{"1.2.840.10008.1.1" => ["1.2.840.10008.1.2.1", "1.2.840.10008.1.2"]}
      ...> )
      {:accept,
       [
         %{id: 1, result: 0, abstract_syntax: "1.2.840.10008.1.1", transfer_syntax: "1.2.840.10008.1.2"},
         %{id: 3, result: 3, abstract_syntax: "1.2.3", transfer_syntax: "1.2.840.10008.1.2"}
       ]}

      iex> Dcmix.Network.Negotiation.negotiate(%{called_ae_title: "OTHER", application_context: "1.2.840.10008.3.1.1.1"},
      ...>   ae_title: "STORE_SCP",
      ...>   abstract_syntaxes: %{}
      ...> )
      {:reject, %{result: 1, source: 1, reason: 7}}
  """

  alias Dcmix.Network.ApplicationContext

  # A-ASSOCIATE-RJ result, source and reason values (PS3.8 Table 9-21)
  @rejected_permanent 1
  @rejected_transient 2
  @source_service_user 1
  @source_service_provider_presentation 3
  @reason_application_context_name_not_supported 2
  @reason_called_ae_title_not_recognized 7
  @reason_local_limit_exceeded 2

  # Presentation context results (PS3.8 Table 9-18)
  @acceptance 0
  @abstract_syntax_not_supported 3
  @transfer_syntaxes_not_supported 4

  @type rejection :: %{result: 1..2, source: 1..3, reason: non_neg_integer()}

  @type context :: %{
          id: non_neg_integer(),
          result: non_neg_integer(),
          abstract_syntax: String.t(),
          transfer_syntax: String.t()
        }

  @doc """
  Negotiates a decoded A-ASSOCIATE-RQ.

  ## Options
  - `:ae_title` - our AE title; the requestor must call it
  - `:abstract_syntaxes` - map of each supported abstract syntax to its
    transfer syntaxes, most preferred first
  """
  @spec negotiate(map(), keyword()) :: {:accept, [context()]} | {:reject, rejection()}
  def negotiate(rq, opts) do
    cond do
      rq.application_context != ApplicationContext.dicom() ->
        {:reject,
         rejection(
           @rejected_permanent,
           @source_service_user,
           @reason_application_context_name_not_supported
         )}

      rq.called_ae_title != String.trim(Keyword.fetch!(opts, :ae_title)) ->
        {:reject,
         rejection(
           @rejected_permanent,
           @source_service_user,
           @reason_called_ae_title_not_recognized
         )}

      true ->
        supported = Keyword.fetch!(opts, :abstract_syntaxes)
        {:accept, Enum.map(rq.presentation_contexts, &negotiate_context(&1, supported))}
    end
  end

  @doc """
  The rejection for an association beyond the SCP's limit: rejected-transient,
  local-limit-exceeded.

      iex> Dcmix.Network.Negotiation.local_limit_exceeded()
      %{result: 2, source: 3, reason: 2}
  """
  @spec local_limit_exceeded() :: rejection()
  def local_limit_exceeded do
    rejection(
      @rejected_transient,
      @source_service_provider_presentation,
      @reason_local_limit_exceeded
    )
  end

  defp rejection(result, source, reason), do: %{result: result, source: source, reason: reason}

  defp negotiate_context(pc, supported) do
    {result, transfer_syntax} =
      case Map.fetch(supported, pc.abstract_syntax) do
        :error -> {@abstract_syntax_not_supported, first_proposed(pc)}
        {:ok, ours} -> choose_transfer_syntax(ours, pc)
      end

    %{
      id: pc.id,
      result: result,
      abstract_syntax: pc.abstract_syntax,
      transfer_syntax: transfer_syntax
    }
  end

  defp choose_transfer_syntax(ours, pc) do
    case Enum.find(ours, &(&1 in pc.transfer_syntaxes)) do
      nil -> {@transfer_syntaxes_not_supported, first_proposed(pc)}
      transfer_syntax -> {@acceptance, transfer_syntax}
    end
  end

  # A rejected context still carries a transfer syntax item, which the
  # requestor ignores
  defp first_proposed(%{transfer_syntaxes: [first | _]}), do: first
  defp first_proposed(_pc), do: ""
end
