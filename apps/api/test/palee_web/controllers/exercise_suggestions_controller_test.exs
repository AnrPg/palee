defmodule PaleeWeb.ExerciseSuggestionsControllerTest do
  @moduledoc """
  ADR-461 over HTTP: suggestions group a person's own names, their box's and
  Palee's; nobody sees another person's or another box's names; the Postgres
  index forgives typos; a name that matches nothing waits for the Palee
  team, whose decision (audited) is what puts it in the «Palee» group.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, add_membership: 3]
  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Application.{CreatePR, RememberExerciseNames}
  alias Palee.Identity.UserContext
  alias Palee.Infrastructure.Security.MemoryRateLimiter
  alias Palee.Organizations
  alias Palee.Workers.RecordExerciseNamesJob
  alias Palee.Workouts.ExerciseNameCandidate

  setup do
    MemoryRateLimiter.reset!()
    # ADR-560: an approval reloads the shared catalog copy; put back the one
    # this test started with once its sandbox rolls back.
    reference = Palee.Catalog.reference()
    on_exit(fn -> Palee.Catalog.put(reference) end)
    :ok
  end

  defp suggest(conn, user, params) do
    conn
    |> recycle()
    |> put_bearer_token(user)
    |> get("/api/me/exercise-suggestions", params)
    |> json_response(200)
  end

  defp names(body, source) do
    body["groups"]
    |> Enum.find(%{"items" => []}, &(&1["source"] == source))
    |> Map.fetch!("items")
    |> Enum.map(& &1["name"])
  end

  defp remember_user(user, names),
    do:
      RememberExerciseNames.call(
        %{scope: :user, user_id: user.id},
        Enum.map(names, &%{"name" => &1}),
        1
      )

  defp remember_org(org, names),
    do:
      RememberExerciseNames.call(
        %{scope: :org, organization_id: org.id},
        Enum.map(names, &%{"name" => &1}),
        1
      )

  test "groups mine, box and palee; typo-tolerant; a name shows once", %{conn: conn} do
    {box, _owner, _context} = organization_fixture()
    member = add_membership(box, user_fixture(), :member)

    :ok = remember_user(member, ["Back Squat", "Back squat pause"])
    :ok = remember_org(box, ["Back Squat", "Back Squat (pause)"])

    body = suggest(conn, member, %{"q" => "bak sqat", "organization_id" => box.id})

    assert Enum.map(body["groups"], & &1["source"]) == ["mine", "box", "palee"]
    assert "Back Squat" in names(body, "mine")
    refute "Back Squat" in names(body, "box")
    refute "Back Squat" in names(body, "palee")

    assert [%{"uses_count" => _, "catalog_slug" => "back-squat"} | _] =
             hd(body["groups"])["items"]

    greek = suggest(conn, member, %{"q" => "σκουατ"})
    assert "Back Squat" in names(greek, "mine")
    assert names(greek, "box") == []
    assert "Front Squat" in names(greek, "palee")

    assert %{"groups" => []} = suggest(conn, member, %{"q" => "  "})
    assert %{"groups" => groups} = suggest(conn, member, %{"q" => "c&j", "limit" => "1"})

    assert [
             %{
               "source" => "palee",
               "items" => [%{"name" => "Clean and Jerk", "hint" => "strength"}]
             }
           ] = groups
  end

  test "nobody sees another person's names or a box they are not in", %{conn: conn} do
    {box, _owner, _context} = organization_fixture()
    {other_box, _other_owner, _other_context} = organization_fixture()
    member = add_membership(box, user_fixture(), :member)
    stranger = user_fixture()

    :ok = remember_user(stranger, ["Zercher Lunge Secret"])
    :ok = remember_org(other_box, ["Zercher Carry Other Box"])
    :ok = remember_org(box, ["Zercher Carry Own Box"])

    body = suggest(conn, member, %{"q" => "zercher", "organization_id" => other_box.id})
    assert body["groups"] == []

    own = suggest(conn, member, %{"q" => "zercher", "organization_id" => box.id})
    assert names(own, "box") == ["Zercher Carry Own Box"]
    assert names(own, "mine") == []

    assert names(suggest(conn, stranger, %{"q" => "zercher"}), "mine") == ["Zercher Lunge Secret"]

    assert suggest(conn, member, %{"q" => "zercher", "organization_id" => "not-a-uuid"})["groups"] ==
             []
  end

  test "a saved PR queues its name; the job remembers it with its catalog link", %{conn: conn} do
    user = user_fixture()

    {:ok, _pr} =
      CreatePR.call(UserContext.new(user), %{
        "name" => "Snatch balance",
        "current_score" => 60,
        "unit" => "kg",
        "beaten_on" => Date.to_iso8601(Date.utc_today()),
        "exercise_ref" => "snatch"
      })

    [job] =
      Palee.Repo.all(
        from(j in Oban.Job,
          where: j.worker == "Palee.Workers.RecordExerciseNamesJob",
          where: fragment("?->>'owner_user_id' = ?", j.args, ^user.id)
        )
      )

    assert :ok = RecordExerciseNamesJob.perform(job)

    body = suggest(conn, user, %{"q" => "snatch bal"})

    assert [%{"name" => "Snatch balance", "catalog_slug" => "snatch"}] =
             hd(body["groups"])["items"]
  end

  test "unmatched names become candidates; only an approved one reaches Palee", %{conn: conn} do
    vendor = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    alice = user_fixture()
    bob = user_fixture()

    :ok = remember_user(alice, ["Sandbag Shouldering", "Back Squat"])
    :ok = remember_user(bob, ["sandbag shouldering"])
    :ok = remember_user(bob, ["sandbag shouldering"])

    assert [%{name: "Sandbag Shouldering", owners_count: 2, uses_count: 3, status: "pending"}] =
             Palee.Repo.all(ExerciseNameCandidate)

    refute "Sandbag Shouldering" in names(suggest(conn, bob, %{"q" => "sandbag"}), "palee")

    assert conn
           |> recycle()
           |> put_bearer_token(alice)
           |> get("/api/platform/exercise-candidates")
           |> json_response(403)

    assert %{
             "candidates" => [%{"id" => id, "name" => "Sandbag Shouldering"}],
             "catalog" => [_ | _]
           } =
             conn
             |> recycle()
             |> put_bearer_token(vendor)
             |> get("/api/platform/exercise-candidates")
             |> json_response(200)

    assert %{"candidate" => %{"status" => "approved", "catalog_slug" => "sandbag-shouldering"}} =
             conn
             |> recycle()
             |> put_bearer_token(vendor)
             |> post("/api/platform/exercise-candidates/#{id}/decision", %{
               "decision" => "entry",
               "label" => "Sandbag Shouldering",
               "category" => "strength",
               "muscles" => [
                 %{"id" => "gluteus-maximus", "role" => "primary"},
                 %{"id" => "erector-spinae", "role" => "secondary"},
                 %{"id" => "obliques", "role" => "stabilizer"}
               ],
               "qualities" => ["strength", "power"]
             })
             |> json_response(200)

    # ADR-560: the new exercise is in the catalog tables with its targets,
    # so Quick Text resolves it and WOD goals are suggested from it.
    assert {:ok, %{id: "sandbag-shouldering"}, :canonical} =
             Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog.resolve("sandbag shouldering")

    assert %{
             muscles: [
               %{id: "gluteus-maximus", role: :primary},
               %{id: "erector-spinae", role: :secondary},
               %{id: "obliques", role: :stabilizer}
             ],
             qualities: ["strength", "power"]
           } = Palee.Anatomy.exercise_targets("sandbag-shouldering")

    assert %{muscles: [%{id: "gluteus-maximus", role: :primary} | _]} =
             Palee.Anatomy.suggest_goals([%{exercise_ref: "sandbag-shouldering", weight: 1}])

    assert conn
           |> recycle()
           |> put_bearer_token(vendor)
           |> post("/api/platform/exercise-candidates/#{id}/decision", %{"decision" => "reject"})
           |> json_response(409)

    stranger = user_fixture()
    assert ["Sandbag Shouldering"] = names(suggest(conn, stranger, %{"q" => "sandbag"}), "palee")

    assert %{
             "events" => [%{"action" => "approve_entry", "catalog_slug" => "sandbag-shouldering"}]
           } =
             conn
             |> recycle()
             |> put_bearer_token(vendor)
             |> get("/api/platform/exercise-catalog-audit")
             |> json_response(200)

    # The WOD editors' catalog (Quick Text manual) has it too.
    {:ok, manual} = Palee.Application.GetWorkoutDslManual.call()
    assert Enum.any?(manual.vocabulary.exercise_catalog, &(&1.id == "sandbag-shouldering"))
  end

  test "the Meilisearch adapter falls back to Postgres when Meilisearch is unreachable", %{
    conn: conn
  } do
    previous = Application.get_env(:palee, :meilisearch)
    Application.put_env(:palee, :meilisearch, url: "http://127.0.0.1:9", log_failures: false)

    Application.put_env(
      :palee,
      :exercise_name_index,
      Palee.Infrastructure.Search.MeilisearchExerciseNameIndex
    )

    on_exit(fn ->
      Application.put_env(:palee, :meilisearch, previous)

      Application.put_env(
        :palee,
        :exercise_name_index,
        Palee.Infrastructure.Search.PostgresExerciseNameIndex
      )
    end)

    user = user_fixture()
    :ok = remember_user(user, ["Wall Ball Shot Ladder"])

    body = suggest(conn, user, %{"q" => "wal bal"})
    assert "Wall Ball Shot Ladder" in names(body, "mine")
    assert "Wall Ball" in names(body, "palee")
  end

  describe "ADR-560: exercise targets in the vendor console" do
    test "vendors list exercises with targets and replace them, audited", %{conn: conn} do
      vendor = user_fixture()
      {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
      athlete = user_fixture()
      as = fn user -> conn |> recycle() |> put_bearer_token(user) end

      assert as.(athlete) |> get("/api/platform/exercise-catalog") |> json_response(403)

      assert as.(athlete)
             |> put("/api/platform/exercise-catalog/deadlift/targets", %{
               "muscles" => [],
               "qualities" => []
             })
             |> json_response(403)

      %{"exercises" => exercises} =
        as.(vendor) |> get("/api/platform/exercise-catalog") |> json_response(200)

      deadlift = Enum.find(exercises, &(&1["id"] == "deadlift"))
      assert %{"origin" => "builtin", "category" => "strength"} = deadlift
      assert %{"id" => "hamstrings", "role" => "primary"} in deadlift["muscles"]
      assert %{"id" => "forearm-flexors", "role" => "stabilizer"} in deadlift["muscles"]
      assert "DL" in deadlift["search_aliases"]

      assert %{"exercise" => %{"muscles" => muscles, "qualities" => ["strength", "power"]}} =
               as.(vendor)
               |> put("/api/platform/exercise-catalog/deadlift/targets", %{
                 "muscles" => [
                   %{"id" => "hamstrings", "role" => "secondary"},
                   %{"id" => "gluteus-maximus", "role" => "primary"},
                   %{"id" => "gluteus-maximus", "role" => "stabilizer"}
                 ],
                 "qualities" => ["power", "strength"]
               })
               |> json_response(200)

      assert muscles == [
               %{"id" => "gluteus-maximus", "role" => "primary"},
               %{"id" => "hamstrings", "role" => "secondary"}
             ]

      assert %{muscles: [%{id: "gluteus-maximus", role: :primary}, %{id: "hamstrings"}]} =
               Palee.Anatomy.exercise_targets("deadlift")

      assert %{
               "events" => [
                 %{"action" => "set_targets", "catalog_slug" => "deadlift"} = event | _
               ]
             } =
               as.(vendor) |> get("/api/platform/exercise-catalog-audit") |> json_response(200)

      assert %{"id" => "forearm-flexors", "role" => "stabilizer"} in event["metadata"]["before"][
               "muscles"
             ]

      assert %{"code" => "invalid_goals"} =
               as.(vendor)
               |> put("/api/platform/exercise-catalog/deadlift/targets", %{
                 "muscles" => [%{"id" => "shoulders", "role" => "primary"}],
                 "qualities" => []
               })
               |> json_response(422)

      assert as.(vendor)
             |> put("/api/platform/exercise-catalog/no-such-move/targets", %{
               "muscles" => [],
               "qualities" => []
             })
             |> json_response(404)
    end
  end
end
