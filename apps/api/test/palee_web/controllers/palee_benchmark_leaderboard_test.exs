defmodule PaleeWeb.PaleeBenchmarkLeaderboardTest do
  @moduledoc """
  ADR-394: the Palee-wide board of a benchmark WOD («Όλο το Palee»), through
  the API under the runtime role's row-level security (every ConnCase
  request), across two boxes. Results never leave their box's tables except
  through the narrow `palee_benchmark_*` functions, and only for people who
  said yes.
  """

  use PaleeWeb.ConnCase, async: false

  alias Palee.{AnalyticsHelpers, DataCase, Organizations, Repo}
  alias Palee.Infrastructure.Tenancy.RepoContext

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, home} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", home.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    {other, other_owner, other_context} = AnalyticsHelpers.organization_fixture()

    %{
      home: home,
      coach: person.(:coach),
      person: person,
      other: other,
      other_owner: other_owner,
      other_context: other_context,
      other_member: fn -> other |> AnalyticsHelpers.member_context() |> elem(0) end,
      as: fn user -> put_bearer_token(conn, user) end,
      base: "/api/org/#{Organizations.legacy_organization_slug()}",
      other_base: "/api/org/#{other.slug}"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp fran(coach, attrs \\ %{}) do
    workout_fixture(
      coach,
      Map.merge(
        %{
          title: "Fran",
          sections: [
            %{
              name: "For time",
              order: 1,
              scoreable: true,
              score_config: %{type: "time"},
              exercises: [%{name: "Thrusters", order: 1, prescription_value: 21}]
            }
          ]
        },
        attrs
      )
    )
  end

  defp tag(as, base, coach, workout, key) do
    as.(coach)
    |> send_json(:put, "#{base}/admin/workouts/#{workout.id}/benchmark", %{benchmark_key: key})
  end

  defp log(as, base, user, workout, time) do
    as.(user)
    |> send_json(:post, "#{base}/me/training-log/entries", %{
      source_type: "library_workout",
      source_reference_id: workout.id,
      performed_at: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601(),
      timezone: "Etc/UTC",
      idempotency_key: "ans-global-" <> Ecto.UUID.generate(),
      section_scores: [%{section_id: hd(workout.sections).id, value: time}]
    })
    |> json_response(201)
  end

  defp answer(as, user, choice) do
    as.(user)
    |> send_json(:put, "/api/me/palee-leaderboard", %{choice: choice})
    |> json_response(200)
  end

  defp board(as, base, user, workout, query \\ "") do
    as.(user) |> get("#{base}/workouts/#{workout.id}/leaderboard?window=all#{query}")
  end

  describe "tagging a WOD as a benchmark" do
    test "the coach picks from the catalog; unknown keys and members are refused", ctx do
      %{as: as, base: base, coach: coach, person: person} = ctx
      workout = fran(coach)

      %{"benchmarks" => catalog} =
        as.(coach) |> get("#{base}/admin/workouts/benchmarks") |> json_response(200)

      keys = Enum.map(catalog, & &1["key"])
      assert length(keys) == 33
      assert "fran" in keys and "murph" in keys and "back_squat" in keys

      assert %{"key" => "murph", "unit" => "mins_secs", "lower_is_better" => true} =
               Enum.find(catalog, &(&1["key"] == "murph"))

      assert %{"benchmark" => %{"key" => "fran", "lower_is_better" => true}} =
               tag(as, base, coach, workout, "fran") |> json_response(200)

      assert %{"code" => "invalid_workout_benchmark"} =
               tag(as, base, coach, workout, "not-a-benchmark") |> json_response(422)

      assert tag(as, base, person.(:member), workout, "fran") |> response(403)

      assert %{"benchmark" => nil} = tag(as, base, coach, workout, nil) |> json_response(200)
    end
  end

  describe "the Palee-wide answer" do
    test "is the person's own, can be changed and withdrawn", ctx do
      %{as: as, person: person} = ctx
      user = person.(:member)

      assert %{"choice" => nil} =
               as.(user) |> get("/api/me/palee-leaderboard") |> json_response(200)

      assert %{"choice" => "see_only"} = answer(as, user, "see_only")
      assert %{"choice" => "share"} = answer(as, user, "share")

      assert %{"errors" => [%{"source" => %{"pointer" => "/choice"}}]} =
               as.(user)
               |> send_json(:put, "/api/me/palee-leaderboard", %{choice: "everyone"})
               |> json_response(422)

      assert %{"choice" => nil} =
               as.(user) |> delete("/api/me/palee-leaderboard") |> json_response(200)

      assert %{"choice" => nil} =
               as.(user) |> get("/api/me/palee-leaderboard") |> json_response(200)
    end
  end

  describe "the «Όλο το Palee» board" do
    setup ctx do
      %{as: as, base: base, other_base: other_base, coach: coach, person: person} = ctx
      home_fran = fran(coach)
      tag(as, base, coach, home_fran, "fran") |> json_response(200)

      other_fran = fran(ctx.other_owner, %{tenant_context: ctx.other_context})
      tag(as, other_base, ctx.other_owner, other_fran, "fran") |> json_response(200)

      # Home: Anna shares, Sofia only sees her place, Nikos never answered.
      [anna, sofia, nikos] = for _ <- 1..3, do: person.(:member)
      # Other box: Kostas and Eleni share, Giorgos never answered, Maria
      # shares but keeps her result private.
      [kostas, eleni, giorgos, maria] = for _ <- 1..4, do: ctx.other_member.()

      for {user, time} <- [{anna, "3:30"}, {sofia, "3:10"}, {nikos, "2:50"}],
          do: log(as, base, user, home_fran, time)

      for {user, time} <- [{kostas, "2:40"}, {eleni, "4:00"}, {giorgos, "2:30"}] do
        log(as, other_base, user, other_fran, time)
      end

      %{"entry" => %{"id" => private_id}} = log(as, other_base, maria, other_fran, "2:00")

      Repo.query!("UPDATE training_log_entries SET journal_visibility = 'private' WHERE id = $1", [
        Ecto.UUID.dump!(private_id)
      ])

      for user <- [anna, kostas, eleni, maria], do: answer(as, user, "share")
      answer(as, sofia, "see_only")

      %{
        home_fran: home_fran,
        other_fran: other_fran,
        anna: anna,
        sofia: sofia,
        nikos: nikos,
        kostas: kostas,
        eleni: eleni,
        giorgos: giorgos
      }
    end

    test "ranks shared results of every box, with box names and no account ids", ctx do
      %{as: as, base: base, home_fran: fran, anna: anna} = ctx

      box = board(as, base, anna, fran) |> json_response(200)
      assert %{"benchmark" => %{"key" => "fran"}, "palee_consent" => "share"} = box
      # The box board never shows the other box.
      refute Enum.any?(box["rows"], &(&1["box_name"] != nil))

      palee = board(as, base, anna, fran, "&scope=palee") |> json_response(200)
      assert %{"filters" => %{"scope" => "palee"}, "total" => 3} = palee

      assert [
               %{"rank" => 1, "value" => "2:40", "user_id" => nil, "me" => false} = first,
               %{"rank" => 2, "value" => "3:30", "me" => true} = mine,
               %{"rank" => 3, "value" => "4:00", "user_id" => nil}
             ] = palee["rows"]

      assert first["nickname"] == ctx.kostas.nickname
      assert first["box_name"] == ctx.other.name
      assert first["avatar_url"] == nil
      assert mine["user_id"] == anna.id
      assert mine["box_name"] == ctx.home.name
      assert palee["me"]["rank"] == 2

      nicknames = Enum.map(palee["rows"], & &1["nickname"])
      # Sofia only sees her own place; Nikos and Giorgos never answered;
      # Maria's result is private.
      refute ctx.sofia.nickname in nicknames
      refute ctx.nikos.nickname in nicknames
      refute ctx.giorgos.nickname in nicknames
    end

    test "«only see my place» ranks the viewer for themselves alone", ctx do
      %{as: as, base: base, home_fran: fran, sofia: sofia} = ctx

      palee = board(as, base, sofia, fran, "&scope=palee") |> json_response(200)
      assert %{"total" => 4, "me" => %{"rank" => 2, "value" => "3:10"}} = palee
      assert [%{"value" => "2:40"}, %{"me" => true} | _] = palee["rows"]
    end

    test "needs an answer and a benchmark WOD", ctx do
      %{as: as, base: base, home_fran: fran, nikos: nikos, coach: coach, anna: anna} = ctx

      assert %{"palee_consent" => nil, "benchmark" => %{"key" => "fran"}} =
               board(as, base, nikos, fran) |> json_response(200)

      assert %{"code" => "palee_leaderboard_consent_required"} =
               board(as, base, nikos, fran, "&scope=palee") |> json_response(409)

      plain = workout_fixture(coach, %{title: "Just a WOD"})

      assert %{"benchmark" => nil, "palee_consent" => nil} =
               board(as, base, anna, plain) |> json_response(200)

      assert %{"code" => "invalid_leaderboard_filter", "field" => "scope"} =
               board(as, base, anna, plain, "&scope=palee") |> json_response(422)

      assert %{"code" => "invalid_leaderboard_filter", "field" => "buddies"} =
               board(as, base, anna, fran, "&scope=palee&buddies=true") |> json_response(422)
    end

    test "division, age group and scale filter the Palee-wide slice", ctx do
      %{as: as, base: base, home_fran: fran, anna: anna} = ctx

      as.(anna)
      |> send_json(:post, "#{base}/landing/leaderboard-opt-in", %{opted_in: true})
      |> json_response(200)

      as.(anna)
      |> send_json(:put, "#{base}/me/leaderboard-profile", %{division: "women", birth_year: 1990})
      |> json_response(200)

      women = board(as, base, anna, fran, "&scope=palee&division=women") |> json_response(200)
      assert [%{"me" => true, "rank" => 1}] = women["rows"]

      year = Date.utc_today().year
      group = Palee.Gamification.Domain.LeaderboardFilters.age_group(1990, year)

      aged = board(as, base, anna, fran, "&scope=palee&age_group=#{group}") |> json_response(200)
      assert [%{"me" => true}] = aged["rows"]

      assert %{"total" => 0} =
               board(as, base, anna, fran, "&scope=palee&scale=no-such-scale")
               |> json_response(200)
    end

    test "withdrawing removes a person from every board at once", ctx do
      %{as: as, base: base, home_fran: fran, anna: anna, kostas: kostas} = ctx

      as.(kostas) |> delete("/api/me/palee-leaderboard") |> json_response(200)

      palee = board(as, base, anna, fran, "&scope=palee") |> json_response(200)
      refute kostas.nickname in Enum.map(palee["rows"], & &1["nickname"])
      assert palee["total"] == 2
    end

    test "box tables stay closed across boxes; the functions need a person", ctx do
      %{anna: anna, other: other} = ctx
      {:ok, context} = Organizations.resolve_tenant_context(anna, Organizations.legacy_organization_slug())
      other_id = Ecto.UUID.dump!(other.id)

      DataCase.with_runtime_role(fn ->
        DataCase.with_clean_session(fn ->
          RepoContext.run(context, fn ->
            # Forced RLS still hides the other box's results and WODs.
            assert %{rows: [[0]]} =
                     Repo.query!(
                       "SELECT count(*) FROM training_log_entries WHERE organization_id = $1",
                       [other_id]
                     )

            assert %{rows: [[0]]} =
                     Repo.query!(
                       "SELECT count(*) FROM master_workouts WHERE organization_id = $1",
                       [other_id]
                     )

            # Nobody else's answer is readable.
            assert %{rows: [[1]]} =
                     Repo.query!("SELECT count(*) FROM palee_leaderboard_consents", [])
          end)

          # Without a person in the session the functions answer nothing.
          assert %{rows: []} =
                   Repo.query!(
                     "SELECT * FROM palee_benchmark_results('fran', '2000-01-01', '2100-01-01', 2026)",
                     []
                   )

          assert %{rows: []} =
                   Repo.query!(
                     "SELECT * FROM palee_benchmark_workout_sections('fran', $1)",
                     [[Ecto.UUID.dump!(ctx.other_fran.id)]]
                   )
        end)
      end)
    end
  end
end
