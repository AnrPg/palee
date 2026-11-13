defmodule Palee.Organizations.Commands.AdmitMember do
  @moduledoc """
  ADR-552: lets an account into a box without the member join link: when it
  starts to buy a package the box lists to everyone (`:purchase`) or when
  the staff accept its «Ζήτα να γίνεις μέλος» (`:accepted_request`, a box
  member at once). ADR-642: starting to buy makes the person a guest of the
  box, marked as a purchase admission; «Το θέλω» or a package makes them a
  member (`MovePurchaseAdmission`).
  `JoinRequestPolicy.admission/2` decides; a former member is let back in
  only by the staff. Runs under the same carve-out as the join link: the
  person is not a member yet, and the staff who accept may not write
  memberships themselves.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{GoLivePolicy, JoinRequestPolicy, PurchaseAdmissionPolicy}
  alias Palee.Organizations.OrganizationStore

  def call(organization_id, user_id, reason, joined_at)
      when is_binary(organization_id) and is_binary(user_id) and
             reason in [:purchase, :accepted_request] do
    RepoContext.run(%{invitation_redemption: true, user_id: user_id}, fn ->
      OrganizationStore.transaction(fn -> admit(organization_id, user_id, reason, joined_at) end)
    end)
  end

  defp admit(organization_id, user_id, reason, joined_at) do
    with %{status: :active} = organization <-
           OrganizationStore.get_organization_by_id(organization_id),
         :ok <- GoLivePolicy.check(organization, :join) do
      membership = OrganizationStore.get_membership(organization.id, user_id)
      settings = OrganizationStore.get_organization_settings(organization.id)

      case JoinRequestPolicy.admission(membership, reason) do
        :already_member ->
          {:ok,
           %{
             organization: organization,
             membership: membership,
             settings: settings,
             created: false
           }}

        :create ->
          with {:ok, created} <-
                 OrganizationStore.add_membership(
                   Map.merge(
                     %{
                       organization_id: organization.id,
                       user_id: user_id,
                       role: :member,
                       status: :active,
                       joined_at: joined_at
                     },
                     admitted_as(reason, joined_at)
                   )
                 ) do
            {:ok,
             %{organization: organization, membership: created, settings: settings, created: true}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
      _unavailable -> {:error, :not_found}
    end
  end

  # ADR-642: a purchase admits a guest until «Το θέλω» or a package.
  defp admitted_as(:purchase, now), do: PurchaseAdmissionPolicy.admitted(now)
  defp admitted_as(_reason, _now), do: %{purchase_admission_at: nil}
end
