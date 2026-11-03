defmodule PaleeWeb.TrainingFloorControllerTest do
  @moduledoc """
  v3.1 «Training and floor» (ADR-356..359) through the API, under the
  production runtime role's row-level security like every ConnCase.
  """

  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo, Scheduling}

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    slug = Organizations.legacy_organization_slug()

    %{
      organization: organization,
      owner: person.(:owner),
      coach: person.(:coach),
      desk: person.(:front_desk),
      person: person,
      as: fn user -> put_bearer_token(conn, user) end,
      slug: slug,
      base: "/api/org/#{slug}"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp fran(coach) do
    workout_fixture(coach, %{
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
    })
  end

  defp log(as, base, user, workout, time) do
    as.(user)
    |> send_json(:post, "#{base}/me/training-log/entries", %{
      source_type: "library_workout",
      source_reference_id: workout.id,
      performed_at: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601(),
      timezone: "Etc/UTC",
      idempotency_key: "w5-" <> Ecto.UUID.generate(),
      section_scores: [%{section_id: hd(workout.sections).id, value: time}]
    })
    |> json_response(201)
  end

  defp tenant(user, slug) do
    {:ok, context} = Organizations.resolve_tenant_context(user, slug)
    context
  end

  defp opt_in(as, base, user) do
    as.(user)
    |> send_json(:post, "#{base}/landing/leaderboard-opt-in", %{opted_in: true})
    |> json_response(200)
  end

  describe "CP-D2 WOD leaderboard" do
    test "filters by division and gives percentiles, only to people who opted in", ctx do
      %{as: as, base: base, coach: coach, person: person} = ctx
      workout = fran(coach)
      people = for _ <- 1..6, do: person.(:member)
      times = ["3:00", "3:30", "4:00", "4:30", "5:00", "5:30"]

      for {user, time} <- Enum.zip(people, times), do: log(as, base, user, workout, time)
      [fast, second | rest] = people
      path = "#{base}/workouts/#{workout.id}/leaderboard?window=all"

      # Not opted in: their own result, no rank, no comparison.
      assert %{"opted_in" => false, "rows" => [], "me" => %{"rank" => nil, "value" => "3:00"}} =
               as.(fast) |> get(path) |> json_response(200)

      # Division needs the opt-in first.
      assert %{"code" => "leaderboard_not_opted_in"} =
               as.(fast)
               |> send_json(:put, "#{base}/me/leaderboard-profile", %{division: "women"})
               |> json_response(409)

      for user <- people, do: opt_in(as, base, user)

      for user <- [fast, second] do
        assert %{"opted_in" => true, "division" => "women", "birth_year" => 1990} =
                 as.(user)
                 |> send_json(:put, "#{base}/me/leaderboard-profile", %{
                   division: "women",
                   birth_year: 1990
                 })
                 |> json_response(200)
      end

      board = as.(List.last(rest)) |> get(path) |> json_response(200)
      assert %{"opted_in" => true, "total" => 6} = board
      assert [%{"rank" => 1, "percentile" => 100, "top_percent" => 17} | _] = board["rows"]

      assert %{"rank" => 6, "percentile" => 0, "top_percent" => 100, "me" => true} =
               board["me"]

      assert "35_39" in board["options"]["age_groups"]

      women = as.(second) |> get(path <> "&division=women") |> json_response(200)
      assert %{"total" => 2, "filters" => %{"division" => "women"}} = women
      # Two results are too few for a percentile.
      assert [%{"rank" => 1, "percentile" => nil}, %{"rank" => 2, "me" => true}] = women["rows"]

      assert %{"total" => 2} =
               as.(second) |> get(path <> "&age_group=35_39") |> json_response(200)

      assert %{"code" => "invalid_leaderboard_filter", "field" => "location_id"} =
               as.(second) |> get(path <> "&scope=branch") |> json_response(422)
    end
  end

  describe "CP-D3 snapshots and day tags" do
    test "a logged score keeps the WOD as it was; editing the WOD later does not change it",
         ctx do
      %{as: as, base: base, coach: coach, person: person} = ctx
      workout = fran(coach)
      member = person.(:member)
      other = person.(:member)
      %{"entry" => %{"id" => entry_id}} = log(as, base, member, workout, "4:00")

      %{rows: [[snapshot_id]]} =
        Repo.query!(
          "SELECT workout_snapshot_id FROM training_log_entries WHERE id = $1",
          [Ecto.UUID.dump!(entry_id)]
        )

      assert snapshot_id
      snapshot_id = Ecto.UUID.load!(snapshot_id)

      # The template (here, the WOD itself) is edited afterwards.
      Repo.query!("UPDATE master_workouts SET title = 'Fran (heavy)' WHERE id = $1", [
        Ecto.UUID.dump!(workout.id)
      ])

      assert %{
               "snapshot" => %{
                 "title" => "Fran",
                 "workout_id" => workout_id,
                 "content" => content
               }
             } =
               as.(member)
               |> get("#{base}/workout-snapshots/#{snapshot_id}")
               |> json_response(200)

      assert workout_id == workout.id
      assert [%{"name" => "For time"}] = content["sections"]

      # Another member does not read someone else's snapshot; staff who program do.
      assert as.(other) |> get("#{base}/workout-snapshots/#{snapshot_id}") |> json_response(404)
      assert as.(coach) |> get("#{base}/workout-snapshots/#{snapshot_id}") |> json_response(200)

      # The same unchanged content is stored once.
      %{"entry" => %{"id" => again}} = log(as, base, other, workout, "4:30")

      %{rows: [[snapshot_again]]} =
        Repo.query!("SELECT workout_snapshot_id FROM training_log_entries WHERE id = $1", [
          Ecto.UUID.dump!(again)
        ])

      # The title changed, so this is a second snapshot of the same WOD.
      refute Ecto.UUID.load!(snapshot_again) == snapshot_id
    end

    test "ADR-389: my own score's WOD as performed, and whether it changed since", ctx do
      %{as: as, base: base, coach: coach, person: person} = ctx
      workout = fran(coach)
      member = person.(:member)
      other = person.(:member)
      %{"entry" => %{"id" => entry_id}} = log(as, base, member, workout, "4:00")
      path = "#{base}/me/training-log/entries/#{entry_id}/workout-snapshot"

      # Unchanged WOD: nothing to show.
      assert %{"changed" => false, "snapshot" => %{"title" => "Fran"}} =
               as.(member) |> get(path) |> json_response(200)

      Repo.query!("UPDATE master_workouts SET title = 'Fran (heavy)' WHERE id = $1", [
        Ecto.UUID.dump!(workout.id)
      ])

      assert %{"changed" => true, "snapshot" => %{"title" => "Fran", "content" => content}} =
               as.(member) |> get(path) |> json_response(200)

      assert [%{"name" => "For time"}] = content["sections"]

      # Someone else's score, and an unknown id, are not found.
      assert as.(other) |> get(path) |> json_response(404)

      assert as.(member)
             |> get("#{base}/me/training-log/entries/#{Ecto.UUID.generate()}/workout-snapshot")
             |> json_response(404)

      # A result from before snapshots shows nothing.
      Repo.query!("UPDATE training_log_entries SET workout_snapshot_id = NULL WHERE id = $1", [
        Ecto.UUID.dump!(entry_id)
      ])

      assert %{"changed" => false, "snapshot" => nil} =
               as.(member) |> get(path) |> json_response(200)
    end

    test "ADR-389: my own run's WOD as performed, changed after an edit", ctx do
      %{as: as, base: base, coach: coach, person: person} = ctx
      workout = fran(coach)
      member = person.(:member)
      %{"entry" => %{"id" => entry_id}} = log(as, base, member, workout, "4:00")

      %{rows: [[snapshot_id]]} =
        Repo.query!("SELECT workout_snapshot_id FROM training_log_entries WHERE id = $1", [
          Ecto.UUID.dump!(entry_id)
        ])

      %{"execution" => %{"id" => execution_id}} =
        as.(member)
        |> send_json(:post, "/api/executions", %{
          master_workout_id: workout.id,
          source: "self_selected"
        })
        |> json_response(201)

      Repo.query!(
        "UPDATE workout_executions SET workout_snapshot_id = $1 WHERE id = $2",
        [snapshot_id, Ecto.UUID.dump!(execution_id)]
      )

      path = "#{base}/me/executions/#{execution_id}/workout-snapshot"

      assert %{"changed" => false, "snapshot" => %{"id" => _}} =
               as.(member) |> get(path) |> json_response(200)

      Repo.query!("UPDATE master_workouts SET description = 'Heavy day' WHERE id = $1", [
        Ecto.UUID.dump!(workout.id)
      ])

      assert %{"changed" => true} = as.(member) |> get(path) |> json_response(200)
      # Another member does not read it.
      assert as.(person.(:member)) |> get(path) |> json_response(404)
    end

    test "day-workouts tags each day not assigned, mixed or all assigned", ctx do
      %{as: as, base: base, coach: coach, owner: owner} = ctx
      workout = fran(coach)
      day = Date.utc_today() |> Date.add(3)
      at = fn hour -> DateTime.new!(day, Time.new!(hour, 0, 0), "Etc/UTC") end
      slot_fixture(workout, %{scheduled_at: at.(9)})
      plain = slot_fixture(workout, %{scheduled_at: at.(18)})

      Repo.query!("UPDATE scheduled_classes SET master_workout_id = NULL WHERE id = $1", [
        Ecto.UUID.dump!(plain.id)
      ])

      response =
        as.(owner)
        |> get("#{base}/admin/schedule/day-workouts?from=#{Date.add(day, -1)}&to=#{day}")
        |> json_response(200)

      assert [
               %{"tag" => "none", "classes" => 0},
               %{"tag" => "mixed", "classes" => 2, "with_wod" => 1}
             ] = response["days"]
    end
  end

  describe "CP-E1 visit badges" do
    test "a first visit and a returning member, on the class list and at the desk", ctx do
      %{as: as, base: base, coach: coach, desk: desk, person: person} = ctx
      workout = fran(coach)
      newcomer = person.(:member)
      regular = person.(:member)
      past = slot_fixture(workout, %{auto_approve: true})
      {:ok, _} = Scheduling.submit_booking(tenant(regular, ctx.slug), regular.id, past.id, 60)

      Repo.query!(
        "UPDATE bookings SET status = 'approved' WHERE scheduled_class_id = $1",
        [Ecto.UUID.dump!(past.id)]
      )

      Repo.query!(
        "UPDATE scheduled_classes SET scheduled_at = now() - interval '2 days' WHERE id = $1",
        [
          Ecto.UUID.dump!(past.id)
        ]
      )

      slot = slot_fixture(workout)

      for user <- [newcomer, regular] do
        {:ok, _} = Scheduling.submit_booking(tenant(user, ctx.slug), user.id, slot.id, 60)
      end

      people =
        as.(desk)
        |> get("#{base}/admin/schedule/slots/#{slot.id}/visit-badges")
        |> json_response(200)
        |> Map.fetch!("people")
        |> Map.new(&{&1["user_id"], &1["badges"]})

      assert people[newcomer.id] == ["first_visit"]
      assert people[regular.id] == []

      assert as.(newcomer)
             |> get("#{base}/admin/schedule/slots/#{slot.id}/visit-badges")
             |> json_response(403)
    end
  end

  describe "CP-E4 calendar invites" do
    test "a booking's invite keeps the feed's UID and turns into a cancellation", ctx do
      %{as: as, base: base, coach: coach, person: person} = ctx
      workout = fran(coach)
      member = person.(:member)
      slot = slot_fixture(workout)

      {:ok, booking} = Scheduling.submit_booking(tenant(member, ctx.slug), member.id, slot.id, 60)

      invite = as.(member) |> get("#{base}/bookings/#{booking.id}/calendar.ics")
      ics = response(invite, 200)
      assert get_resp_header(invite, "content-type") |> hd() =~ "text/calendar"
      assert ics =~ "UID:class-#{slot.id}@palee"
      assert ics =~ "METHOD:PUBLISH"
      assert ics =~ "STATUS:TENTATIVE"
      [_, first_sequence] = Regex.run(~r/SEQUENCE:(\d+)/, ics)

      Repo.query!(
        "UPDATE bookings SET status = 'cancelled', updated_at = now() + interval '1 minute' WHERE id = $1",
        [Ecto.UUID.dump!(booking.id)]
      )

      cancelled =
        as.(member) |> get("#{base}/bookings/#{booking.id}/calendar.ics") |> response(200)

      assert cancelled =~ "METHOD:CANCEL"
      assert cancelled =~ "STATUS:CANCELLED"
      assert cancelled =~ "UID:class-#{slot.id}@palee"
      [_, sequence] = Regex.run(~r/SEQUENCE:(\d+)/, cancelled)
      assert String.to_integer(sequence) > String.to_integer(first_sequence)

      # The feed keeps the cancelled seat as CANCELLED so calendars drop it.
      links = as.(member) |> get("/api/calendar/export-links") |> json_response(200)

      feed =
        build_conn() |> get("/api/calendar/feed.ics", %{token: links["token"]}) |> response(200)

      assert feed =~ "UID:class-#{slot.id}@palee"
      assert feed =~ "STATUS:CANCELLED"

      # Someone else's booking is not found.
      assert as.(person.(:member))
             |> get("#{base}/bookings/#{booking.id}/calendar.ics")
             |> json_response(404)
    end
  end

  describe "CP-D6 fitness profile" do
    test "scores from the person's own PRs, with the reasoning", ctx do
      %{as: as, person: person} = ctx
      member = person.(:member)

      for {name, unit, score} <- [{"Back squat", "kg", 140}, {"Fran", "mins_secs", 360}] do
        as.(member)
        |> post("/api/prs", %{
          "name" => name,
          "current_score" => score,
          "unit" => unit,
          "beaten_on" => Date.to_iso8601(Date.utc_today())
        })
        |> json_response(201)
      end

      profile = as.(member) |> get("/api/me/fitness-profile?division=men") |> json_response(200)

      assert %{"algorithm" => %{"id" => "fitness-profile", "version" => 2}} = profile
      # Back squat 140 kg: 64.3 points (between 120 and 155); Fran 6:00: 42.5.
      assert %{"score" => 54, "domains_scored" => 2} = profile["overall"]

      strength = Enum.find(profile["domains"], &(&1["domain"] == "strength"))

      assert %{"score" => 64, "reasons" => [%{"benchmark" => "back_squat", "points" => 64.3}]} =
               strength

      assert as.(member) |> get("/api/me/fitness-profile?division=x") |> json_response(422)
    end
  end

  describe "ADR-395 fitness card version 2" do
    test "the person's own settings: body weight, birth year, what the card shows", ctx do
      %{as: as, person: person} = ctx
      member = person.(:member)

      assert %{"body_weight_kg" => nil, "birth_year" => nil, "display" => "all"} =
               as.(member) |> get("/api/me/fitness-profile/settings") |> json_response(200)

      assert %{"body_weight_kg" => 60.0, "display" => "all"} =
               as.(member)
               |> send_json(:put, "/api/me/fitness-profile/settings", %{body_weight_kg: 60})
               |> json_response(200)

      assert %{"body_weight_kg" => 60.0, "birth_year" => 1985, "display" => "progress_only"} =
               as.(member)
               |> send_json(:put, "/api/me/fitness-profile/settings", %{
                 birth_year: 1985,
                 display: "progress_only"
               })
               |> json_response(200)

      assert as.(member)
             |> send_json(:put, "/api/me/fitness-profile/settings", %{body_weight_kg: 5})
             |> json_response(422)

      as.(member)
      |> post("/api/prs", %{
        "name" => "Back squat",
        "current_score" => 70,
        "unit" => "kg",
        "beaten_on" => Date.to_iso8601(Date.utc_today()),
        "supporting_metrics" => %{"reps" => 3}
      })
      |> json_response(201)

      shown = as.(member) |> get("/api/me/fitness-profile?division=women") |> json_response(200)
      assert %{"display" => %{"mode" => "progress_only", "set_by" => "self"}} = shown
      assert shown["overall"] == nil
      strength = Enum.find(shown["domains"], &(&1["domain"] == "strength"))
      assert strength["tested"] == true
      refute Map.has_key?(strength, "score")

      as.(member)
      |> send_json(:put, "/api/me/fitness-profile/settings", %{display: "all"})
      |> json_response(200)

      full =
        as.(member)
        |> get("/api/me/fitness-profile?division=women&period=12w")
        |> json_response(200)

      # Born 1985: the 40–44 band, 8% easier for women (ADR-395 age bands).
      assert %{
               "inputs" => %{
                 "body_weight_kg" => 60.0,
                 "age_ready" => true,
                 "age_band" => band,
                 "age_percent" => percent
               }
             } = full

      assert {band, percent} in [{"40_44", 8}, {"35_39", 5}]
      assert is_binary(full["period_from"])

      [reason] = Enum.find(full["domains"], &(&1["domain"] == "strength"))["reasons"]

      assert %{"basis" => "body_weight", "ratio" => 1.28, "next" => %{"points" => 75}} = reason
      # The PR is new within the period: no earlier score to compare with.
      assert Enum.find(full["domains"], &(&1["domain"] == "strength"))["change"] == nil

      assert as.(member) |> get("/api/me/fitness-profile?period=2w") |> json_response(422)
    end

    test "only the client's coach reads their settings and chooses what the card shows", ctx do
      %{as: as, base: base, coach: coach, owner: owner, person: person} = ctx
      member = person.(:member)

      as.(member)
      |> send_json(:put, "/api/me/fitness-profile/settings", %{body_weight_kg: 72.5})
      |> json_response(200)

      path = "#{base}/staff/clients/#{member.id}/fitness-display"

      # Not their coach (yet): nothing, owners included.
      assert as.(coach) |> get(path) |> json_response(403)
      assert as.(owner) |> get(path) |> json_response(403)

      {:ok, _} =
        Palee.Coaching.start_relationship(%{organization_id: ctx.organization.id}, %{
          coach_user_id: coach.id,
          client_user_id: member.id,
          origin: "assigned"
        })

      assert %{"settings" => %{"body_weight_kg" => 72.5, "display" => "all"}, "override" => nil} =
               as.(coach) |> get(path) |> json_response(200)

      assert %{"override" => "none"} =
               as.(coach) |> send_json(:put, path, %{display: "none"}) |> json_response(200)

      assert as.(coach) |> send_json(:put, path, %{display: "all"}) |> json_response(422)

      shown = as.(member) |> get("/api/me/fitness-profile") |> json_response(200)
      assert %{"display" => %{"mode" => "none", "set_by" => "coach"}, "domains" => []} = shown

      assert %{"override" => nil} =
               as.(coach) |> send_json(:put, path, %{display: nil}) |> json_response(200)

      assert %{"display" => %{"mode" => "all", "set_by" => "self"}} =
               as.(member) |> get("/api/me/fitness-profile") |> json_response(200)
    end
  end

  describe "CP-E5 staff notes" do
    test "the front desk writes and reads staff notes, never a coach's private ones", ctx do
      %{as: as, base: base, coach: coach, desk: desk, owner: owner, person: person} = ctx
      member = person.(:member)

      {:ok, _} =
        Palee.Coaching.start_relationship(%{organization_id: ctx.organization.id}, %{
          coach_user_id: coach.id,
          client_user_id: member.id,
          origin: "assigned"
        })

      path = "#{base}/staff/clients/#{member.id}/coach-notes"

      assert %{"note" => %{"audience" => "private"}} =
               as.(coach) |> send_json(:post, path, %{body: "Knee history"}) |> json_response(201)

      assert %{"note" => %{"id" => staff_note, "audience" => "staff"}} =
               as.(desk)
               |> send_json(:post, path, %{body: "Prefers the 7:00", audience: "staff"})
               |> json_response(201)

      assert [%{"id" => ^staff_note}] =
               as.(desk) |> get(path) |> json_response(200) |> Map.fetch!("notes")

      coach_sees = as.(coach) |> get(path) |> json_response(200) |> Map.fetch!("notes")
      assert length(coach_sees) == 2

      assert length(as.(owner) |> get(path) |> json_response(200) |> Map.fetch!("notes")) == 2

      # The desk cannot write a private coach note.
      assert as.(desk) |> send_json(:post, path, %{body: "x"}) |> json_response(403)
    end
  end
end
