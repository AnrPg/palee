defmodule PaleeWeb.ChangeClientRolesTest do
  @moduledoc "ADR-812: box roles of clients changed from the finance ledger."
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo}

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    accountant = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(accountant, :accountant)

    %{
      organization: organization,
      owner_conn: put_bearer_token(conn, owner),
      accountant_conn: put_bearer_token(conn, accountant),
      path: "/api/org/#{Organizations.legacy_organization_slug()}/admin/users/roles/changes"
    }
  end

  defp client(role) do
    user = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
    user
  end

  defp post_json(conn, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp roles_of(organization, user), do: Organizations.member_roles(organization.id, user.id)

  test "a preview changes nothing and says what would happen", %{
    owner_conn: conn,
    organization: organization,
    path: path
  } do
    member = client(:member)

    assert %{"results" => [result]} =
             conn
             |> post_json("#{path}/preview", %{
               user_ids: [member.id],
               add: ["athlete"],
               remove: ["member"]
             })
             |> json_response(200)

    assert result["status"] == "preview"
    assert result["roles"] == ["athlete"]
    # Still an athlete, so still a client: nothing is cancelled.
    assert result["impact"] == %{"future_bookings" => 0, "kept_package" => nil}
    assert roles_of(organization, member) == [:member]
  end

  test "a bulk change adds and removes only the named roles, person by person", %{
    owner_conn: conn,
    organization: organization,
    path: path
  } do
    member = client(:member)
    athlete = client(:athlete)
    coach_member = client(:coach)

    {:ok, _} =
      Organizations.set_membership_roles(owner_context(), coach_member.id, [:coach, :member])

    assert %{"results" => results} =
             conn
             |> post_json(path, %{
               user_ids: [member.id, athlete.id, coach_member.id],
               add: ["athlete"]
             })
             |> json_response(200)

    by_user = Map.new(results, &{&1["user_id"], &1})
    assert by_user[member.id]["status"] == "changed"
    assert by_user[athlete.id]["status"] == "unchanged"
    assert by_user[coach_member.id]["roles"] == ["coach", "member", "athlete"]

    assert roles_of(organization, member) == [:member, :athlete]
    assert roles_of(organization, coach_member) == [:coach, :member, :athlete]
  end

  test "a change that leaves no client role is refused for that person only", %{
    owner_conn: conn,
    organization: organization,
    path: path
  } do
    member = client(:member)
    both = client(:athlete)
    {:ok, _} = Organizations.set_membership_roles(owner_context(), both.id, [:member, :athlete])

    assert %{"results" => results} =
             conn
             |> post_json(path, %{user_ids: [member.id, both.id], remove: ["member"]})
             |> json_response(200)

    by_user = Map.new(results, &{&1["user_id"], &1})
    assert %{"status" => "refused", "code" => "client_role_required"} = by_user[member.id]
    assert by_user[both.id]["status"] == "changed"
    assert roles_of(organization, member) == [:member]
    assert roles_of(organization, both) == [:athlete]
  end

  test "staff without the right to change roles cannot change or preview", %{
    accountant_conn: conn,
    path: path
  } do
    member = client(:member)

    assert conn
           |> post_json("#{path}/preview", %{user_ids: [member.id], add: ["athlete"]})
           |> json_response(403)
  end

  test "a request names at least one role", %{owner_conn: conn, path: path} do
    member = client(:member)

    assert %{"code" => "roles_required"} =
             conn |> post_json(path, %{user_ids: [member.id]}) |> json_response(422)
  end

  test "the ledger lists every role, client roles first", %{owner_conn: conn} do
    coach_member = client(:coach)

    {:ok, _} =
      Organizations.set_membership_roles(owner_context(), coach_member.id, [:coach, :member])

    %{"members" => members} =
      conn
      |> recycle()
      |> get("/api/org/#{Organizations.legacy_organization_slug()}/admin/finance/members")
      |> json_response(200)

    row = Enum.find(members, &(&1["id"] == coach_member.id))
    assert row["roles"] == ["member", "coach"]
  end

  defp owner_context do
    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner, Organizations.legacy_organization_slug())

    context
  end
end
