defmodule PaleeWeb.FinanceCleanupRecordsControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Organizations}

  import Palee.TestFixtures

  # ADR-797: «Εκκαθάριση συναλλαγών» over HTTP, filters to side panel.
  test "lists with filters and pages, then loads one record's details", %{conn: conn} do
    admin = admin_fixture(%{nickname: "cleanup_admin"})
    member = user_fixture(%{role: :member, nickname: "cleanup_member"})
    {organization, context} = tenant_fixture(admin, "Cleanup Tenant")
    add_tenant_member(organization, member, :member)

    {:ok, package} =
      Finance.create_package(context, %{
        name: "Cleanup package",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 5_000
      })

    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, subscription} = Finance.assign_package(context, membership.id, package.id, %{})

    base = "/api/org/#{organization.slug}/admin/finance/cleanup-records"

    conn
    |> put_bearer_token(admin)
    |> post("/api/org/#{organization.slug}/admin/finance/members/#{member.id}/receipts", %{
      amount_cents: 5_000,
      payment_method: "cash",
      paid_on: "2026-11-20",
      description: "Monthly membership",
      membership_package_subscription_id: subscription.id,
      idempotency_key: Ecto.UUID.generate()
    })
    |> json_response(201)

    listed =
      conn
      |> put_bearer_token(admin)
      |> get(base, %{
        q: "cleanup_mem",
        kind: "payment",
        package_id: package.id,
        from: "2026-11-01",
        to: "2026-11-30",
        limit: "1"
      })
      |> json_response(200)

    assert [payment] = listed["records"]
    assert listed["next_cursor"] == nil
    assert payment["record_type"] == "payment"
    assert payment["customer_name"] == member.nickname
    assert payment["package_name"] == "Cleanup package"
    assert payment["payment_method"] == "cash"
    assert payment["occurred_on"] == "2026-11-20"

    details =
      conn
      |> put_bearer_token(admin)
      |> get("#{base}/#{payment["id"]}", %{record_type: "payment"})
      |> json_response(200)

    assert details["record"]["created_by_name"] == admin.nickname
    assert [%{"record_type" => "receipt"}] = details["record"]["linked"]

    packages =
      conn
      |> put_bearer_token(admin)
      |> get("#{base}/packages")
      |> json_response(200)

    assert [%{"name" => "Cleanup package", "active" => true}] = packages["packages"]

    conn
    |> put_bearer_token(admin)
    |> get("#{base}/#{Ecto.UUID.generate()}", %{record_type: "payment"})
    |> json_response(404)
  end

  test "staff without billing rights cannot read the records", %{conn: conn} do
    admin = admin_fixture()
    coach = user_fixture(%{role: :member})
    {organization, _context} = tenant_fixture(admin, "Cleanup Rights")
    add_tenant_member(organization, coach, :coach)

    conn
    |> put_bearer_token(coach)
    |> get("/api/org/#{organization.slug}/admin/finance/cleanup-records")
    |> json_response(403)
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
