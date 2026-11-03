defmodule PaleeWeb.LoggedWorkoutChangeTest do
  @moduledoc """
  ADR-393 through the API, under the production runtime role's row-level
  security like every ConnCase: when staff save a WOD that people already
  logged, only the people whose score now reads differently hear it, once per
  save, with a link to that entry in their Journal.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Notifications, Organizations, Repo}

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    # ADR-184: a business in demo mode notifies nobody.
    activate_business!(organization.id)

    person = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      user
    end

    coach = person.(:coach)

    workout =
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

    %{
      coach: coach,
      person: person,
      workout: workout,
      as: fn user -> put_bearer_token(conn, user) end,
      base: "/api/org/#{Organizations.legacy_organization_slug()}"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp log(%{as: as, base: base, workout: workout}, user, time) do
    %{"entry" => %{"id" => id}} =
      as.(user)
      |> send_json(:post, "#{base}/me/training-log/entries", %{
        source_type: "library_workout",
        source_reference_id: workout.id,
        performed_at: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601(),
        timezone: "Etc/UTC",
        idempotency_key: "ans-" <> Ecto.UUID.generate(),
        section_scores: [%{section_id: hd(workout.sections).id, value: time}]
      })
      |> json_response(201)

    id
  end

  defp revision(workout_id) do
    %{rows: [[revision]]} =
      Repo.query!("SELECT dsl_source_revision FROM master_workouts WHERE id = $1", [
        Ecto.UUID.dump!(workout_id)
      ])

    revision
  end

  # The editor's save: reopen, change the draft, publish (one save).
  defp edit(%{as: as, base: base, workout: workout}, editor, reps) do
    path = "#{base}/admin/workouts/#{workout.id}"
    as.(editor) |> send_json(:post, "#{path}/reopen", %{}) |> json_response(200)

    %{"draft" => %{"dsl_source_revision" => draft_revision}} =
      as.(editor)
      |> send_json(:patch, "#{path}/draft", %{
        expected_source_revision: revision(workout.id),
        draft_data: %{
          "title" => "Fran",
          "type" => "crossfit",
          "sections" => [
            %{
              "name" => "For time",
              "order" => 1,
              "scoreable" => true,
              "score_config" => %{"type" => "time"},
              "exercises" => [
                %{"name" => "Thrusters", "order" => 1, "prescription_value" => reps}
              ]
            }
          ]
        }
      })
      |> json_response(200)

    as.(editor)
    |> send_json(:post, "#{path}/publish", %{expected_source_revision: draft_revision})
    |> json_response(200)
  end

  defp notices(user),
    do: user.id |> Notifications.list_for_user() |> Enum.filter(&(to_string(&1.type) == "logged_workout_changed"))

  test "only the people who logged it hear it, once per save, never the editor", ctx do
    %{coach: coach, person: person} = ctx
    athlete = person.(:member)
    other = person.(:member)
    bystander = person.(:member)
    before_snapshots = person.(:member)

    athlete_entry = log(ctx, athlete, "4:00")
    log(ctx, other, "5:10")
    log(ctx, coach, "3:30")
    old_entry = log(ctx, before_snapshots, "6:00")

    # A score from before snapshots has nothing to compare (ADR-389 shows nothing).
    Repo.query!("UPDATE training_log_entries SET workout_snapshot_id = NULL WHERE id = $1", [
      Ecto.UUID.dump!(old_entry)
    ])

    edit(ctx, coach, 15)

    assert [notice] = notices(athlete)
    assert notice.payload["url"] == "/journal?entry=#{athlete_entry}"
    assert notice.payload["holder"] == "training_log"
    assert notice.payload["holder_id"] == athlete_entry
    assert notice.payload["workout_title"] == "Fran"
    assert notice.payload["workout_id"] == ctx.workout.id

    assert [_one] = notices(other)
    assert notices(coach) == []
    assert notices(bystander) == []
    assert notices(before_snapshots) == []

    # The link lands on an entry that shows «Το WOD άλλαξε από τότε».
    assert %{"changed" => true} =
             ctx.as.(athlete)
             |> get("#{ctx.base}/me/training-log/entries/#{athlete_entry}/workout-snapshot")
             |> json_response(200)

    # A second save changes it again: one more notice, still one per save.
    edit(ctx, coach, 9)
    assert length(notices(athlete)) == 2
  end

  test "a person who logged it twice hears once, about the latest; muting the coach category stops it",
       ctx do
    %{coach: coach, person: person} = ctx
    athlete = person.(:member)
    muted = person.(:member)
    log(ctx, athlete, "4:30")
    latest = log(ctx, athlete, "4:00")
    log(ctx, muted, "5:00")

    ctx.as.(muted)
    |> send_json(:put, "/api/notifications/preferences/coach", %{in_app: false})
    |> json_response(200)

    edit(ctx, coach, 15)

    assert [notice] = notices(athlete)
    assert notice.payload["holder_id"] == latest
    assert notices(muted) == []
  end

  test "a booked person who logged it gets this notice instead of «Η προπόνηση άλλαξε»", ctx do
    %{coach: coach, person: person, workout: workout} = ctx
    logged = person.(:member)
    booked = person.(:member)
    slot = slot_fixture(workout, %{auto_approve: true})
    {:ok, context} = Organizations.resolve_tenant_context(coach, Organizations.legacy_organization_slug())

    for user <- [logged, booked] do
      {:ok, _booking} =
        Palee.Scheduling.submit_auto_approved_booking_with(context, user.id, slot.id, %{})
    end

    log(ctx, logged, "4:00")
    edit(ctx, coach, 15)

    changed = fn user ->
      user.id |> Notifications.list_for_user() |> Enum.filter(&(to_string(&1.type) == "workout_changed"))
    end

    assert [_notice] = notices(logged)
    assert changed.(logged) == []
    assert notices(booked) == []
    assert [_upcoming] = changed.(booked)
  end

  test "another staff member's save reaches the coach who logged it", ctx do
    %{coach: coach, person: person} = ctx
    owner = person.(:owner)
    log(ctx, coach, "3:30")
    edit(ctx, owner, 15)
    assert [_notice] = notices(coach)
    assert notices(owner) == []
  end
end
