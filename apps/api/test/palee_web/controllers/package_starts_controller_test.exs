defmodule PaleeWeb.PackageStartsControllerTest do
  @moduledoc """
  ADR-795 over HTTP: the member's «Το κατάλαβα» on a package that changed
  while it waited, and staff's «Να μην εμφανιστεί ξανά σήμερα».
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations}

  setup %{conn: conn} do
    owner = user_fixture()
    member = user_fixture()

    {:ok, box} =
      Organizations.create_organization(%{name: "Box #{System.unique_integer([:positive])}"})

    add!(box, owner, [:owner])
    add!(box, member, [:member])

    {:ok, staff} = Organizations.resolve_tenant_context(owner, box.slug)

    {:ok, _settings} =
      Finance.update_finance_settings(staff, %{package_starts_with: "first_session"})

    {:ok, package} =
      Finance.create_package(staff, %{
        code: "monthly-#{System.unique_integer([:positive])}",
        name: "Μηνιαίο",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 5_000
      })

    {:ok, membership} =
      Finance.upsert_membership(staff, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, subscription} = Finance.assign_package(staff, membership.id, package.id, %{})

    %{
      conn: conn,
      owner: owner,
      member: member,
      box: box,
      staff: staff,
      package: package,
      subscription: subscription
    }
  end

  defp authed(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  test "the member sees what changed and starts the package with «Το κατάλαβα»", ctx do
    assert {:ok, _saved} =
             Finance.update_package_with_terms(
               ctx.staff,
               ctx.package.id,
               %{"name" => ctx.package.name, "base_price_cents" => 6_000},
               %{apply_to: nil},
               ctx.owner.id
             )

    assert {:ok, {:review, start}} =
             Finance.begin_package_start(ctx.staff, ctx.subscription.id, %{
               kind: "class",
               id: Ecto.UUID.generate(),
               on: Organizations.local_today(ctx.box.id)
             })

    billing = ctx.conn |> authed(ctx.member) |> get("/api/me/billing") |> json_response(200)
    [provider] = Enum.filter(billing["providers"], &(&1["slug"] == ctx.box.slug))

    assert [%{"package_start" => %{"status" => "review", "severity" => "important"}}] =
             provider["subscriptions"]

    path = "/api/org/#{ctx.box.slug}/me/membership/package-starts/#{start.id}/acknowledge"
    body = ctx.conn |> authed(ctx.member) |> post(path) |> json_response(200)
    assert body["package_start"]["status"] == "started"

    assert ctx.conn |> authed(ctx.member) |> post(path) |> json_response(404)
  end

  test "«Να μην εμφανιστεί ξανά σήμερα» per staff member and box day", ctx do
    path = "/api/org/#{ctx.box.slug}/admin/confirmation-skips"
    assert %{"skipped" => []} = ctx.conn |> authed(ctx.owner) |> get(path) |> json_response(200)

    assert %{"skipped" => ["record_payment"]} =
             ctx.conn
             |> authed(ctx.owner)
             |> post(path, %{kind: "record_payment"})
             |> json_response(200)

    assert %{"skipped" => ["record_payment"]} =
             ctx.conn |> authed(ctx.owner) |> get(path) |> json_response(200)

    assert ctx.conn |> authed(ctx.owner) |> post(path, %{kind: "nope"}) |> json_response(422)
    assert ctx.conn |> authed(ctx.member) |> get(path) |> json_response(403)
  end

  defp add!(organization, user, roles) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: hd(roles),
        roles: roles,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
