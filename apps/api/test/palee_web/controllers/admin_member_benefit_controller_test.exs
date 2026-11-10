defmodule PaleeWeb.AdminMemberBenefitControllerTest do
  @moduledoc "ADR-612: «Δώρο ή χάρη»: staff who take payments give, revoke, and everyone sees who, when and why."
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations}

  @plan %{
    "entitlement_version" => 1,
    "channels" => ["in_person"],
    "capabilities" => ["book_classes"],
    "allowances" => %{"class_visits" => %{"limit" => 3, "period" => "calendar_month"}}
  }

  setup do
    admin = admin_fixture(%{nickname: "gift_admin"})
    member = user_fixture(%{role: :member, nickname: "gift_member"})
    {organization, context} = tenant_fixture(admin, "Gift Tenant")
    add_tenant_member(organization, member, :member)

    {:ok, package} =
      Finance.create_package(context, %{
        name: "Three a month",
        family: "limited-visits",
        billing_period: "monthly",
        base_price_cents: 5_000,
        params: @plan
      })

    %{
      admin: admin,
      member: member,
      organization: organization,
      context: context,
      package: package
    }
  end

  defp benefits_path(ctx, suffix \\ ""),
    do:
      "/api/org/#{ctx.organization.slug}/admin/finance/members/#{ctx.member.id}/benefits#{suffix}"

  defp give(conn, ctx, body, as \\ nil) do
    conn
    |> put_bearer_token(as || ctx.admin)
    |> post(benefits_path(ctx), Map.put_new(body, "idempotency_key", Ecto.UUID.generate()))
  end

  defp history(conn, ctx, as \\ nil) do
    conn
    |> put_bearer_token(as || ctx.admin)
    |> get(benefits_path(ctx))
    |> json_response(200)
    |> Map.fetch!("benefits")
  end

  defp member_with_package(ctx) do
    {:ok, membership} =
      Finance.upsert_membership(ctx.context, ctx.member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, subscription} =
      Finance.assign_package(ctx.context, membership.id, ctx.package.id, %{
        starts_on: Date.utc_today()
      })

    {membership, subscription}
  end

  defp membership(ctx), do: Finance.get_member_profile(ctx.context, ctx.member.id).membership

  test "free access opens access for someone without a package, with who, when and why",
       %{conn: conn} = ctx do
    ends_on = Date.add(Date.utc_today(), 14)

    ref =
      :telemetry_test.attach_event_handlers(self(), [
        [:palee, :finance, :member_benefit, :granted]
      ])

    benefit =
      conn
      |> give(ctx, %{
        "kind" => "free_access",
        "ends_on" => Date.to_iso8601(ends_on),
        "reason" => "Trial for a friend of the box"
      })
      |> json_response(201)
      |> Map.fetch!("benefit")

    assert benefit["kind"] == "free_access"
    assert benefit["state"] == "active"
    assert benefit["ends_on"] == Date.to_iso8601(ends_on)
    assert benefit["reason"] == "Trial for a friend of the box"
    assert benefit["given_by_id"] == ctx.admin.id
    assert "owner" in benefit["given_by_roles"]
    assert benefit["revocation"] == nil

    assert_received {[:palee, :finance, :member_benefit, :granted], ^ref, %{count: 1},
                     %{kind: "free_access"}}

    membership = membership(ctx)
    assert membership.entitlement_status == "active"
    assert membership.entitlement_source == "staff_free_access"

    assert [%{"kind" => "free_access"}] = history(conn, ctx)
  end

  test "a grace keeps access until its date and revoking it ends it at once",
       %{conn: conn} = ctx do
    member_with_package(ctx)
    ends_on = Date.add(Date.utc_today(), 5)

    benefit =
      conn
      |> give(ctx, %{"kind" => "grace", "ends_on" => Date.to_iso8601(ends_on)})
      |> json_response(201)
      |> Map.fetch!("benefit")

    assert benefit["reason"] == nil
    membership = membership(ctx)
    assert membership.entitlement_source == "staff_grace"
    assert membership.entitlement_grace_until == ends_on

    revoked =
      conn
      |> put_bearer_token(ctx.admin)
      |> post(benefits_path(ctx, "/#{benefit["id"]}/revoke"), %{
        "idempotency_key" => Ecto.UUID.generate(),
        "reason" => "Paid at the desk"
      })
      |> json_response(200)
      |> Map.fetch!("benefit")

    assert revoked["state"] == "revoked"
    assert revoked["revocation"]["by_id"] == ctx.admin.id
    assert revoked["revocation"]["reason"] == "Paid at the desk"
    refute membership(ctx).entitlement_source == "staff_grace"

    assert conn
           |> put_bearer_token(ctx.admin)
           |> post(benefits_path(ctx, "/#{benefit["id"]}/revoke"), %{
             "idempotency_key" => Ecto.UUID.generate()
           })
           |> json_response(409)
           |> Map.fetch!("code") == "benefit_already_revoked"
  end

  test "extra uses add to the allowance for the period staff chose", %{conn: conn} = ctx do
    member_with_package(ctx)

    benefit =
      conn
      |> give(ctx, %{
        "kind" => "extra_uses",
        "allowance" => "class_visits",
        "quantity" => 1,
        "period" => "calendar_month"
      })
      |> json_response(201)
      |> Map.fetch!("benefit")

    assert benefit["details"]["quantity"] == 1
    assert benefit["details"]["usage_entry_id"]
    assert benefit["starts_on"]
    assert benefit["ends_on"]

    assert conn
           |> put_bearer_token(ctx.admin)
           |> post(benefits_path(ctx, "/#{benefit["id"]}/revoke"), %{
             "idempotency_key" => Ecto.UUID.generate()
           })
           |> json_response(200)
           |> get_in(["benefit", "state"]) == "revoked"
  end

  test "extra uses need the period", %{conn: conn} = ctx do
    member_with_package(ctx)

    assert conn
           |> give(ctx, %{"kind" => "extra_uses", "allowance" => "class_visits", "quantity" => 1})
           |> json_response(422)
           |> Map.fetch!("code") == "benefit_period_required"
  end

  test "a package given free this period starts charging next period", %{conn: conn} = ctx do
    benefit =
      conn
      |> give(ctx, %{
        "kind" => "package",
        "package_id" => ctx.package.id,
        "pricing" => %{"mode" => "this_period_free"}
      })
      |> json_response(201)
      |> Map.fetch!("benefit")

    assert benefit["details"]["package_name"] == "Three a month"
    assert benefit["details"]["pricing"] == "this_period_free"
    assert benefit["amount_cents"] == 5_000
    assert benefit["details"]["subscription_id"]
    assert benefit["state"] == "given"

    assert conn
           |> put_bearer_token(ctx.admin)
           |> post(benefits_path(ctx, "/#{benefit["id"]}/revoke"), %{
             "idempotency_key" => Ecto.UUID.generate()
           })
           |> json_response(409)
           |> Map.fetch!("code") == "benefit_not_revocable"
  end

  test "a package at a lower price records what the box gives up", %{conn: conn} = ctx do
    benefit =
      conn
      |> give(ctx, %{
        "kind" => "package",
        "package_id" => ctx.package.id,
        "pricing" => %{"mode" => "price", "price_cents" => 3_000}
      })
      |> json_response(201)
      |> Map.fetch!("benefit")

    assert benefit["details"]["price_cents"] == 3_000
    assert benefit["amount_cents"] == 2_000
  end

  test "forgiving a charge settles it without money and without a document",
       %{conn: conn} = ctx do
    {membership, subscription} = member_with_package(ctx)

    {:ok, invoice} =
      Finance.create_invoice(ctx.context, membership.id, %{
        membership_package_subscription_id: subscription.id,
        amount_cents: 5_000
      })

    {:ok, _issued} = Finance.issue_invoice(ctx.context, invoice.id, %{})

    benefit =
      conn
      |> give(ctx, %{"kind" => "debt_forgiven", "invoice_ids" => [invoice.id]})
      |> json_response(201)
      |> Map.fetch!("benefit")

    assert benefit["amount_cents"] == 5_000

    assert [%{"invoice_id" => invoice_id, "amount_cents" => 5_000}] =
             benefit["details"]["invoices"]

    assert invoice_id == invoice.id

    assert {:ok, %{status: "paid"}} = Finance.get_invoice(ctx.context, invoice.id)

    assert conn
           |> give(ctx, %{"kind" => "debt_forgiven", "invoice_ids" => [invoice.id]})
           |> json_response(409)
           |> Map.fetch!("code") == "invoice_nothing_owed"
  end

  test "the same idempotency key gives once", %{conn: conn} = ctx do
    body = %{
      "kind" => "free_access",
      "ends_on" => Date.to_iso8601(Date.add(Date.utc_today(), 3)),
      "idempotency_key" => Ecto.UUID.generate()
    }

    first = conn |> give(ctx, body) |> json_response(201)
    again = build_conn() |> give(ctx, body) |> json_response(200)

    assert again["replayed"] == true
    assert again["benefit"]["id"] == first["benefit"]["id"]
    assert length(history(build_conn(), ctx)) == 1
  end

  test "the reason is optional but at most 500 characters, and the end date can't be past",
       %{conn: conn} = ctx do
    assert conn
           |> give(ctx, %{
             "kind" => "free_access",
             "ends_on" => Date.to_iso8601(Date.add(Date.utc_today(), 3)),
             "reason" => String.duplicate("a", 501)
           })
           |> json_response(422)
           |> Map.fetch!("code") == "benefit_reason_too_long"

    assert build_conn()
           |> give(ctx, %{
             "kind" => "grace",
             "ends_on" => Date.to_iso8601(Date.add(Date.utc_today(), -1))
           })
           |> json_response(422)
           |> Map.fetch!("code") == "benefit_ends_in_past"
  end

  test "staff who don't take payments can't give", %{conn: conn} = ctx do
    coach = user_fixture(%{nickname: "gift_coach"})
    add_tenant_member(ctx.organization, coach, :coach)

    conn =
      give(
        conn,
        ctx,
        %{"kind" => "free_access", "ends_on" => Date.to_iso8601(Date.add(Date.utc_today(), 3))},
        coach
      )

    assert conn.status == 403
  end

  test "the ledger refuses an update", ctx do
    {:ok, _result} =
      Palee.Application.MemberBenefits.grant(ctx.context, ctx.member.id, %{
        "kind" => "free_access",
        "ends_on" => Date.to_iso8601(Date.add(Date.utc_today(), 3)),
        "idempotency_key" => Ecto.UUID.generate()
      })

    assert_raise Postgrex.Error, ~r/insert-only|append-only|cannot be changed/i, fn ->
      Finance.with_tenant_context(ctx.context, fn ->
        Palee.Repo.query!("UPDATE finance_member_benefits SET reason = 'changed'")
      end)
    end
  end

  defp tenant_fixture(user, name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    add_tenant_member(organization, user, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    {organization, context}
  end

  defp add_tenant_member(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end
end
