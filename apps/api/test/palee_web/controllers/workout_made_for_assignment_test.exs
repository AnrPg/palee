defmodule PaleeWeb.WorkoutMadeForAssignmentTest do
  @moduledoc """
  ADR-680: a WOD made for one day, class, athlete or member («+ Νέο WOD»
  inside that screen) lives only in that thing's library folder: its first
  filing moves it there instead of leaving it at the root with a copy.
  """

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.{Organizations, Repo, Workouts}
  alias Palee.Workouts.MasterWorkout

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture(%{nickname: "made_for_admin"})
    athlete = user_fixture(%{nickname: "made_for_athlete", role: :athlete})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(athlete)
    # ADR-225: athletes are programmed through their package.
    programming_grant_fixture(organization.id, athlete)

    %{
      organization: organization,
      admin: admin,
      athlete: athlete,
      crossfit: class_type_fixture(%{name: "CrossFit"})
    }
  end

  defp path(suffix), do: "/api/org/#{Organizations.legacy_organization_slug()}#{suffix}"

  defp json_conn(conn, user),
    do: conn |> put_bearer_token(user) |> put_req_header("content-type", "application/json")

  defp tenant(ctx), do: %{organization_id: ctx.organization.id, location_scope: :all}

  defp day(ctx), do: Date.add(Organizations.local_today(ctx.organization.id), 2)

  defp at(ctx, time) do
    ctx
    |> day()
    |> DateTime.new!(time, Organizations.organization_timezone(ctx.organization.id))
    |> DateTime.shift_zone!("Etc/UTC")
  end

  # A published WOD as «+ Νέο WOD» leaves it: at the root, awaiting filing.
  defp made_for_assignment(ctx, title) do
    workout = workout_fixture(ctx.admin, %{title: title})

    {:ok, _} =
      Workouts.update_library_metadata(tenant(ctx), workout.id, %{awaiting_filing: true})

    workout
  end

  defp stored(ctx, id), do: Workouts.get_workout_for_admin(tenant(ctx), id)

  defp folder_key(ctx, folder_id) do
    tenant(ctx)
    |> Workouts.list_folders()
    |> Enum.find(&(&1.id == folder_id))
    |> case do
      nil -> nil
      folder -> folder[:system_key]
    end
  end

  defp copies_of(id),
    do: Repo.aggregate(from(w in MasterWorkout, where: w.source_workout_id == ^id), :count)

  defp class_body(ctx, attrs) do
    Map.merge(
      %{
        class_type_id: ctx.crossfit.id,
        name: "CrossFit class",
        scheduled_at: at(ctx, ~T[18:00:00]),
        capacity: 10,
        auto_approve: true,
        booking_timeout_minutes: 30
      },
      attrs
    )
  end

  test "«+ Νέο WOD» creates a draft that awaits filing", %{conn: conn} = ctx do
    draft =
      conn
      |> json_conn(ctx.admin)
      |> post(path("/admin/workouts"), Jason.encode!(%{awaiting_filing: true}))
      |> json_response(201)
      |> Map.fetch!("draft")

    assert %{awaiting_filing: true, folder_id: nil} = stored(ctx, draft["id"])

    plain =
      conn
      |> recycle()
      |> json_conn(ctx.admin)
      |> post(path("/admin/workouts"), Jason.encode!(%{}))
      |> json_response(201)
      |> Map.fetch!("draft")

    assert %{awaiting_filing: false} = stored(ctx, plain["id"])
  end

  test "a day's new WOD moves into the day's folder and is not left at the root",
       %{conn: conn} = ctx do
    workout = made_for_assignment(ctx, "Day WOD")

    result =
      conn
      |> json_conn(ctx.admin)
      |> put(
        path("/admin/schedule/day-workouts"),
        Jason.encode!(%{date: day(ctx), master_workout_id: workout.id})
      )
      |> json_response(200)

    assert [%{"master_workout_id" => filed_id}] = result["day_workouts"]
    assert filed_id == workout.id

    moved = stored(ctx, workout.id)
    assert moved.awaiting_filing == false
    assert folder_key(ctx, moved.folder_id) == "classes:#{Date.to_iso8601(day(ctx))}"
    assert copies_of(workout.id) == 0
  end

  test "a library template given to a day is still copied, the template stays put",
       %{conn: conn} = ctx do
    template = workout_fixture(ctx.admin, %{title: "Template"})

    conn
    |> json_conn(ctx.admin)
    |> put(
      path("/admin/schedule/day-workouts"),
      Jason.encode!(%{date: day(ctx), master_workout_id: template.id})
    )
    |> json_response(200)

    assert stored(ctx, template.id).folder_id == nil
    assert copies_of(template.id) == 1
  end

  test "a new class's new WOD moves into the class's day folder", %{conn: conn} = ctx do
    workout = made_for_assignment(ctx, "Class WOD")

    slot =
      conn
      |> json_conn(ctx.admin)
      |> post(
        path("/admin/schedule/slots"),
        Jason.encode!(class_body(ctx, %{master_workout_id: workout.id}))
      )
      |> json_response(201)
      |> Map.fetch!("slot")

    assert slot["master_workout_id"] == workout.id
    moved = stored(ctx, workout.id)
    assert folder_key(ctx, moved.folder_id) == "classes:#{Date.to_iso8601(day(ctx))}"
    assert moved.awaiting_filing == false
    assert copies_of(workout.id) == 0
  end

  test "creating a class with a library template files nothing", %{conn: conn} = ctx do
    template = workout_fixture(ctx.admin, %{title: "Class template"})

    conn
    |> json_conn(ctx.admin)
    |> post(
      path("/admin/schedule/slots"),
      Jason.encode!(class_body(ctx, %{master_workout_id: template.id}))
    )
    |> json_response(201)

    assert stored(ctx, template.id).folder_id == nil
    assert copies_of(template.id) == 0
  end

  test "an existing class's new WOD moves into the day folder",
       %{conn: conn} = ctx do
    slot =
      conn
      |> json_conn(ctx.admin)
      |> post(path("/admin/schedule/slots"), Jason.encode!(class_body(ctx, %{})))
      |> json_response(201)
      |> Map.fetch!("slot")

    workout = made_for_assignment(ctx, "Linked WOD")

    conn
    |> recycle()
    |> json_conn(ctx.admin)
    |> put(
      path("/admin/schedule/slots/#{slot["id"]}/workout"),
      Jason.encode!(%{master_workout_id: workout.id})
    )
    |> json_response(200)

    moved = stored(ctx, workout.id)
    assert folder_key(ctx, moved.folder_id) == "classes:#{Date.to_iso8601(day(ctx))}"
    assert copies_of(workout.id) == 0
  end

  test "athletes' new WOD moves into the first athlete's folder; the others get copies",
       %{conn: conn} = ctx do
    workout = made_for_assignment(ctx, "Athlete WOD")
    other = user_fixture(%{nickname: "made_for_other", role: :athlete})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(other)
    programming_grant_fixture(ctx.organization.id, other)

    response =
      conn
      |> json_conn(ctx.admin)
      |> post(
        path("/admin/assigned-workouts"),
        Jason.encode!(%{
          master_workout_id: workout.id,
          athlete_ids: [ctx.athlete.id, other.id],
          scheduled_for: Date.utc_today()
        })
      )
      |> json_response(201)

    assert [first, second] = response["assignments"]
    assert first["master_workout_id"] == workout.id
    moved = stored(ctx, workout.id)
    assert folder_key(ctx, moved.folder_id) == "athlete:#{hd(first["athlete_ids"])}"

    copy = stored(ctx, second["master_workout_id"])
    assert copy.source_workout_id == workout.id
    assert folder_key(ctx, copy.folder_id) == "athlete:#{hd(second["athlete_ids"])}"
    assert copy.awaiting_filing == false
  end

  test "moving a WOD by hand files it: it no longer awaits filing", %{conn: conn} = ctx do
    workout = made_for_assignment(ctx, "Moved by hand")

    {:ok, folder} =
      Workouts.create_folder(tenant(ctx), ctx.admin.id, %{name: "Strength", parent_id: nil})

    conn
    |> json_conn(ctx.admin)
    |> patch(
      path("/admin/workouts/#{workout.id}/library"),
      Jason.encode!(%{folder_id: folder.id})
    )
    |> json_response(200)

    assert %{awaiting_filing: false} = moved = stored(ctx, workout.id)
    assert moved.folder_id == folder.id
  end
end
