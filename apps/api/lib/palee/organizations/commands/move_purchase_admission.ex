defmodule Palee.Organizations.Commands.MovePurchaseAdmission do
  @moduledoc """
  ADR-642: moves a purchase admission on (`PurchaseAdmissionPolicy`) when
  «Το θέλω» is sent, when a package starts and when a request closes with no
  package. Runs in the person's own scope under the same carve-out as
  `AdmitMember`: the person writes only their own row, and only `roles`
  between guest and member and the mark. Returns `{:ok, :promoted |
  :settled | :demoted | :unchanged}`; a promotion is announced as
  `:membership_activated` (club, leads, referrals), as any other way in.
  """

  require Logger

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.PurchaseAdmissionPolicy
  alias Palee.Organizations.OrganizationStore

  @doc "«Το θέλω» was sent."
  def request_sent(organization_id, user_id, now \\ DateTime.utc_now()),
    do: move(organization_id, user_id, &PurchaseAdmissionPolicy.on_request(&1, now))

  @doc "A package started for the person."
  def package_started(organization_id, user_id),
    do: move(organization_id, user_id, &PurchaseAdmissionPolicy.on_package/1)

  @doc "A request closed with no package; `kept?` says whether anything still holds them."
  def request_closed(organization_id, user_id, kept?),
    do: move(organization_id, user_id, &PurchaseAdmissionPolicy.on_request_closed(&1, kept?))

  defp move(organization_id, user_id, decide)
       when is_binary(organization_id) and is_binary(user_id) do
    result =
      RepoContext.run(%{invitation_redemption: true, user_id: user_id}, fn ->
        OrganizationStore.transaction(fn -> apply_decision(organization_id, user_id, decide) end)
      end)

    case result do
      {:ok, :promoted} ->
        Palee.DomainEvents.publish(:membership_activated, %{
          organization_id: organization_id,
          user_id: user_id,
          at: DateTime.utc_now()
        })

        {:ok, :promoted}

      {:ok, outcome} ->
        {:ok, outcome}

      # The purchase or the request already happened; the membership catches
      # up on the next step (a package, another request, a later closure).
      {:error, reason} ->
        Logger.warning(
          "purchase_admission_not_moved organization_id=#{organization_id} " <>
            "user_id=#{user_id} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp apply_decision(organization_id, user_id, decide) do
    case OrganizationStore.get_membership(organization_id, user_id) do
      %{status: :active, left_at: nil} = membership ->
        case decide.(membership) do
          {outcome, attrs} -> write(organization_id, user_id, attrs, outcome)
          :keep -> {:ok, :unchanged}
        end

      _none_or_former ->
        {:ok, :unchanged}
    end
  end

  defp write(organization_id, user_id, attrs, outcome) do
    with {:ok, _membership} <-
           OrganizationStore.set_purchase_admission(organization_id, user_id, attrs) do
      {:ok, past(outcome)}
    end
  end

  defp past(:promote), do: :promoted
  defp past(:settle), do: :settled
  defp past(:demote), do: :demoted
end
