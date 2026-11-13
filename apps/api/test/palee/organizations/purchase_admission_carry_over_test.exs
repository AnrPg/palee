defmodule Palee.Organizations.PurchaseAdmissionCarryOverTest do
  @moduledoc """
  ADR-642: the 20271113530000 carry-over makes a guest again only whoever
  came in by starting to buy and never got anywhere: a request or an online
  package payment within ten minutes of joining, no Finance profile, no
  request still waiting. Everyone else stays a member.
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations, Repo}
  alias Palee.Finance.PackageRequest
  alias Palee.Organizations.OrganizationMembership

  @migration Palee.Repo.Migrations.PurchaseAdmission
  @migration_file "priv/repo/migrations/20271113530000_purchase_admission.exs"

  setup_all do
    unless Code.ensure_loaded?(@migration),
      do: Code.require_file(Application.app_dir(:palee, @migration_file))

    :ok
  end

  setup do
    owner = admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Carry Over Box #{System.unique_integer([:positive])}"
      })

    {:ok, _owner} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, package} =
      Finance.create_package(context, %{
        name: "Μηνιαίο",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 5_000
      })

    %{organization: organization, context: context, package: package}
  end

  defp member!(ctx) do
    user = user_fixture()

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: ctx.organization.id,
        user_id: user.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp request!(ctx, user, status) do
    Repo.insert!(%PackageRequest{
      organization_id: ctx.organization.id,
      user_id: user.id,
      membership_package_id: ctx.package.id,
      package_name_snapshot: "Μηνιαίο",
      price_cents_snapshot: 5_000,
      currency: "EUR",
      status: status,
      source: "member",
      requested_by_id: user.id,
      hold_until: Date.add(Date.utc_today(), 14),
      closed_at: if(status == "pending", do: nil, else: DateTime.utc_now()),
      decline_reason: if(status == "declined", do: "Γεμάτο", else: nil)
    })
  end

  defp roles(ctx, user),
    do:
      Repo.get_by!(OrganizationMembership, organization_id: ctx.organization.id, user_id: user.id).roles

  test "a buyer whose only request closed is a guest again; the rest stay members", ctx do
    gave_up = member!(ctx)
    request!(ctx, gave_up, "declined")

    waiting = member!(ctx)
    request!(ctx, waiting, "pending")

    paid = member!(ctx)
    request!(ctx, paid, "lapsed")

    {:ok, _profile} =
      Finance.upsert_membership(ctx.context, paid.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    by_link = member!(ctx)

    Repo.query!(apply(@migration, :carry_over_sql, []))

    assert roles(ctx, gave_up) == [:guest]
    assert roles(ctx, waiting) == [:member]
    assert roles(ctx, paid) == [:member]
    assert roles(ctx, by_link) == [:member]
  end
end
