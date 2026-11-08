defmodule Palee.Web.ProfileCardControllerTest do
  @moduledoc """
  ADR-554 (Εγώ as the profile): «Λίγα λόγια», the tabs a profile shows and
  the «Διακρίσεις» tab, which only the owner and their active followers see,
  and followers only while the owner shows it.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Gamification.UserAchievement
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  setup %{conn: conn} do
    %{
      owner: user_fixture(),
      follower: user_fixture(),
      stranger: user_fixture(),
      as: fn user -> put_bearer_token(conn, user) end
    }
  end

  defp put_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(path, Jason.encode!(body))
  end

  defp follow!(as, follower, person) do
    assert %{"status" => "active"} =
             as.(follower)
             |> put_req_header("content-type", "application/json")
             |> post(
               "/api/me/follows",
               Jason.encode!(%{target_type: "user", target_id: person.id})
             )
             |> json_response(200)
  end

  defp badge!(user, key) do
    {:ok, _badge} =
      RepoContext.run(%{user_id: user.id}, fn ->
        Repo.insert(%UserAchievement{
          user_id: user.id,
          badge_key: key,
          earned_at: DateTime.utc_now()
        })
      end)
  end

  test "a profile starts with «Πολυμέσα · Αναρτήσεις» and no bio", %{
    as: as,
    owner: owner,
    stranger: stranger
  } do
    assert %{"tabs" => ["media", "posts"], "bio" => nil} =
             as.(stranger) |> get("/api/people/#{owner.id}") |> json_response(200)
  end

  test "the owner sets «Λίγα λόγια» and adds tabs; everyone reads them",
       %{as: as, owner: owner, stranger: stranger} do
    assert %{"bio" => "Olympic lifting, 7:00.", "tabs" => ["media", "posts", "badges", "prs"]} =
             as.(owner)
             |> put_json("/api/me/profile-card", %{
               bio: "  Olympic lifting, 7:00. ",
               tabs: ["badges", "prs"]
             })
             |> json_response(200)

    assert %{"bio" => "Olympic lifting, 7:00.", "tabs" => ["media", "posts", "badges", "prs"]} =
             as.(stranger) |> get("/api/people/#{owner.id}") |> json_response(200)

    # Only the field sent changes; a blank bio clears it.
    assert %{"bio" => "Olympic lifting, 7:00.", "tabs" => ["media", "posts", "prs"]} =
             as.(owner)
             |> put_json("/api/me/profile-card", %{tabs: ["prs"]})
             |> json_response(200)

    assert %{"bio" => nil, "tabs" => ["media", "posts", "prs"]} =
             as.(owner) |> put_json("/api/me/profile-card", %{bio: "   "}) |> json_response(200)
  end

  test "unknown tabs and an overlong bio are refused", %{as: as, owner: owner} do
    assert as.(owner) |> put_json("/api/me/profile-card", %{tabs: ["notes"]}) |> response(422)

    assert as.(owner)
           |> put_json("/api/me/profile-card", %{bio: String.duplicate("a", 151)})
           |> response(422)
  end

  test "«Διακρίσεις»: the owner always, followers only while the tab is shown",
       %{as: as, owner: owner, follower: follower, stranger: stranger} do
    badge!(owner, "workouts_10")
    follow!(as, follower, owner)

    assert %{
             "badges" => [%{"badge_key" => "workouts_10", "label" => "10 Workouts"}],
             "locked" => false
           } =
             as.(owner) |> get("/api/people/#{owner.id}/badges") |> json_response(200)

    # The tab is not shown yet: a follower sees none, not even through RLS.
    assert %{"badges" => [], "locked" => false} =
             as.(follower) |> get("/api/people/#{owner.id}/badges") |> json_response(200)

    as.(owner) |> put_json("/api/me/profile-card", %{tabs: ["badges"]}) |> json_response(200)

    assert %{"badges" => [%{"badge_key" => "workouts_10"}], "locked" => false} =
             as.(follower) |> get("/api/people/#{owner.id}/badges") |> json_response(200)

    assert %{"badges" => [], "locked" => true} =
             as.(stranger) |> get("/api/people/#{owner.id}/badges") |> json_response(200)
  end
end
