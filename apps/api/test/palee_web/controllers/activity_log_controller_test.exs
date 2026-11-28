defmodule PaleeWeb.ActivityLogControllerTest do
  @moduledoc """
  ADR-760: the box's «Αρχείο ενεργειών». A staff change is recorded once, with
  who, when, about whom and why; each role reads its own areas (4A); the
  member reads only what staff shared with them, as «Το box» (5A); the CSV
  goes to who may export (10A).
  """
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Organizations

  setup do
    admin = admin_fixture(%{nickname: "log_admin"})
    member = user_fixture(%{role: :member, nickname: "log_member"})
    coach = user_fixture(%{role: :member, nickname: "log_coach"})
    {organization, context} = tenant_fixture(admin, "Log Tenant")
    add_tenant_member(organization, member, :member)
    add_tenant_member(organization, coach, :coach)

    %{admin: admin, member: member, coach: coach, organization: organization, context: context}
  end

  defp org(ctx, path), do: "/api/org/#{ctx.organization.slug}#{path}"

  defp give(conn, ctx, body) do
    conn
    |> put_bearer_token(ctx.admin)
    |> post(
      org(ctx, "/admin/finance/members/#{ctx.member.id}/benefits"),
      Map.merge(
        %{
          "kind" => "free_access",
          "ends_on" => Date.to_iso8601(Date.add(Date.utc_today(), 7)),
          "idempotency_key" => Ecto.UUID.generate()
        },
        body
      )
    )
  end

  defp log(conn, as, ctx, query \\ "") do
    conn
    |> put_bearer_token(as)
    |> get(org(ctx, "/admin/activity-log" <> query))
  end

  test "a gift is recorded once with who, about whom and why", %{conn: conn} = ctx do
    key = Ecto.UUID.generate()
    body = %{"reason" => "Friend of the box", "idempotency_key" => key}

    assert %{status: 201} = give(conn, ctx, body)
    # The same request again is a replay: nothing new happened.
    assert %{status: 200} = give(build_conn(), ctx, body)

    page = conn |> log(ctx.admin, ctx) |> json_response(200)

    assert [entry] = page["entries"]
    assert entry["action"] == "benefit.give"
    assert entry["area"] == "money"
    assert entry["sensitive"] == true
    assert entry["reason"] == "Friend of the box"
    assert entry["reason_shared"] == false
    assert entry["actor"]["id"] == ctx.admin.id
    assert entry["person"]["id"] == ctx.member.id
    assert page["can_export"] == true
    assert "money" in page["areas"]

    # Filtered to the person (the profile tab «Ιστορικό»).
    assert [_] =
             log(build_conn(), ctx.admin, ctx, "?person_id=#{ctx.member.id}")
             |> json_response(200)
             |> Map.fetch!("entries")

    assert [] =
             log(build_conn(), ctx.admin, ctx, "?person_id=#{ctx.coach.id}")
             |> json_response(200)
             |> Map.fetch!("entries")
  end

  test "?sensitive=true keeps only the sensitive actions (the owner's summary link)",
       %{conn: conn} = ctx do
    assert %{status: 201} = give(conn, ctx, %{})

    {:ok, _} =
      Palee.ActivityLog.record(ctx.context, %{
        action: "package.freeze",
        person_user_id: ctx.member.id
      })

    all = log(build_conn(), ctx.admin, ctx) |> json_response(200) |> Map.fetch!("entries")
    assert length(all) == 2

    assert [%{"action" => "benefit.give"}] =
             log(build_conn(), ctx.admin, ctx, "?sensitive=true")
             |> json_response(200)
             |> Map.fetch!("entries")
  end

  test "the member sees only what staff shared, as the box", %{conn: conn} = ctx do
    assert %{status: 201} = give(conn, ctx, %{"reason" => "kept private"})

    assert %{status: 201} =
             give(build_conn(), ctx, %{"reason" => "Welcome week", "reason_shared" => true})

    entries =
      build_conn()
      |> put_bearer_token(ctx.member)
      |> get(org(ctx, "/me/membership/activity"))
      |> json_response(200)
      |> Map.fetch!("entries")

    assert [entry] = entries
    assert entry["reason"] == "Welcome week"
    refute Map.has_key?(entry, "actor")
  end

  test "a coach reads only classes and their own pay; no money, no CSV", %{conn: conn} = ctx do
    assert %{status: 201} = give(conn, ctx, %{})

    page = build_conn() |> log(ctx.coach, ctx) |> json_response(200)
    assert page["entries"] == []
    assert page["can_export"] == false
    refute "money" in page["areas"]
    assert "classes" in page["areas"]

    assert %{status: 403} =
             build_conn()
             |> put_bearer_token(ctx.coach)
             |> get(org(ctx, "/admin/activity-log/export"))
  end

  test "the CSV has the rows the reader sees", %{conn: conn} = ctx do
    assert %{status: 201} = give(conn, ctx, %{"reason" => "=cmd()"})

    resp =
      build_conn()
      |> put_bearer_token(ctx.admin)
      |> get(org(ctx, "/admin/activity-log/export"))

    assert resp.status == 200
    assert [type | _] = get_resp_header(resp, "content-type")
    assert type =~ "text/csv"
    [header, row] = resp.resp_body |> String.trim() |> String.split(~r/\r?\n/)
    assert header =~ "occurred_at"
    assert row =~ "benefit.give"
    # A cell that would run as a formula in a spreadsheet is quoted.
    assert row =~ "'=cmd()"
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
