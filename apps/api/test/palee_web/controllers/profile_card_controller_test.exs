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

  # The rows below sit in tables only their owner or the box reads; the test
  # role bypasses RLS, and the definers decide who gets them.
  defp box_with_belt!(owner) do
    {organization, _admin, _context} = Palee.AnalyticsHelpers.organization_fixture()
    Palee.AnalyticsHelpers.add_membership(organization, owner, :member)
    org = Ecto.UUID.dump!(organization.id)
    user = Ecto.UUID.dump!(owner.id)
    ladder = Ecto.UUID.bingenerate()
    rank = Ecto.UUID.bingenerate()

    Repo.query!(
      """
      INSERT INTO rank_ladders (id, organization_id, name, discipline, inserted_at, updated_at)
      VALUES ($1, $2, 'BJJ', 'bjj', now(), now())
      """,
      [ladder, org]
    )

    Repo.query!(
      """
      INSERT INTO ranks (id, organization_id, ladder_id, position, name, color, max_stripes, inserted_at, updated_at)
      VALUES ($1, $2, $3, 2, 'Purple', 'purple', 4, now(), now())
      """,
      [rank, org, ladder]
    )

    Repo.query!(
      """
      INSERT INTO rank_awards (id, organization_id, ladder_id, rank_id, user_id, stripes, awarded_on,
                               certificate_number, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, $2, $3, $4, 2, CURRENT_DATE, $5, now(), now())
      """,
      [org, ladder, rank, user, "C-#{System.unique_integer([:positive])}"]
    )

    organization
  end

  defp workout!(owner, visibility) do
    Repo.query!(
      """
      INSERT INTO workout_executions (id, user_id, source, status, started_at_utc, completed_at_utc,
                                      completed_at_tz, total_elapsed_ms, journal_visibility, inserted_at)
      VALUES (gen_random_uuid(), $1, 'self_selected', 'completed', now() - interval '1 hour', now(),
              'Europe/Athens', 1200000, $2, now())
      """,
      [Ecto.UUID.dump!(owner.id), visibility]
    )
  end

  test "the box and belt show only once picked, to the owner and followers",
       %{as: as, owner: owner, follower: follower, stranger: stranger} do
    organization = box_with_belt!(owner)
    follow!(as, follower, owner)

    assert %{"box" => nil, "box_id" => nil, "show_rank" => false} =
             as.(owner) |> get("/api/people/#{owner.id}") |> json_response(200)

    assert %{"box_id" => box_id, "show_rank" => true} =
             as.(owner)
             |> put_json("/api/me/profile-card", %{box_id: organization.id, show_rank: true})
             |> json_response(200)

    assert box_id == organization.id

    for reader <- [owner, follower] do
      assert %{
               "box" => %{
                 "name" => name,
                 "slug" => slug,
                 "rank" => %{"name" => "Purple", "color" => "purple", "stripes" => 2}
               }
             } = as.(reader) |> get("/api/people/#{owner.id}") |> json_response(200)

      assert {name, slug} == {organization.name, organization.slug}
    end

    # Others never see the owner's choices, and strangers not the box.
    assert %{"box_id" => nil, "show_rank" => false} =
             as.(follower) |> get("/api/people/#{owner.id}") |> json_response(200)

    assert %{"box" => nil} =
             as.(stranger) |> get("/api/people/#{owner.id}") |> json_response(200)

    as.(owner) |> put_json("/api/me/profile-card", %{show_rank: false}) |> json_response(200)

    assert %{"box" => %{"rank" => nil}} =
             as.(follower) |> get("/api/people/#{owner.id}") |> json_response(200)
  end

  test "a box you are not a member of cannot be shown", %{as: as, owner: owner} do
    {organization, _admin, _context} = Palee.AnalyticsHelpers.organization_fixture()

    assert as.(owner)
           |> put_json("/api/me/profile-card", %{box_id: organization.id})
           |> response(422)
  end

  test "«Προπονήσεις» and «Πρόοδος»: followers see them only while the tab is shown",
       %{as: as, owner: owner, follower: follower, stranger: stranger} do
    workout!(owner, "coach_can_view")
    workout!(owner, "private")
    follow!(as, follower, owner)

    Repo.query!(
      """
      INSERT INTO user_stats (id, user_id, total_workouts, current_streak, longest_streak, total_prs, updated_at)
      VALUES (gen_random_uuid(), $1, 42, 3, 9, 5, now())
      """,
      [Ecto.UUID.dump!(owner.id)]
    )

    assert %{"workouts" => [], "locked" => false} =
             as.(follower) |> get("/api/people/#{owner.id}/workouts") |> json_response(200)

    assert %{"progress" => nil} =
             as.(follower) |> get("/api/people/#{owner.id}/progress") |> json_response(200)

    as.(owner)
    |> put_json("/api/me/profile-card", %{tabs: ["workouts", "progress"]})
    |> json_response(200)

    # «Μόνο εγώ» workouts stay off the profile, even for the owner.
    for reader <- [owner, follower] do
      assert %{"workouts" => [%{"elapsed_ms" => 1_200_000, "completed_tz" => "Europe/Athens"}]} =
               as.(reader) |> get("/api/people/#{owner.id}/workouts") |> json_response(200)

      assert %{
               "progress" => %{
                 "total_workouts" => 42,
                 "current_streak" => 3,
                 "longest_streak" => 9,
                 "total_prs" => 5
               }
             } = as.(reader) |> get("/api/people/#{owner.id}/progress") |> json_response(200)
    end

    assert %{"workouts" => [], "locked" => true} =
             as.(stranger) |> get("/api/people/#{owner.id}/workouts") |> json_response(200)

    assert %{"progress" => nil, "locked" => true} =
             as.(stranger) |> get("/api/people/#{owner.id}/progress") |> json_response(200)
  end
end
