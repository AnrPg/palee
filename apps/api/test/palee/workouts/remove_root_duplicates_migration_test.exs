defmodule Palee.Workouts.RemoveRootDuplicatesMigrationTest do
  @moduledoc """
  ADR-680: the 20271121130000 migration removes the root original of a WOD
  that was made for a day, class, athlete or member and filed as a copy,
  keeping the copy (with the original's goals), and leaves templates alone.
  """

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Palee.TestFixtures

  alias Palee.{Organizations, Repo, Workouts}

  @version 20_271_121_130_000
  @migration Palee.Repo.Migrations.RemoveRootDuplicatesOfFiledWods
  @migration_file "priv/repo/migrations/20271121130000_remove_root_duplicates_of_filed_wods.exs"

  setup_all do
    unless Code.ensure_loaded?(@migration) do
      Code.require_file(Application.app_dir(:palee, @migration_file))
    end

    :ok
  end

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    admin = admin_fixture(%{nickname: "dup_cleanup_admin"})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)

    %{organization: organization, admin: admin, crossfit: class_type_fixture(%{name: "CrossFit"})}
  end

  defp path(suffix), do: "/api/org/#{Organizations.legacy_organization_slug()}#{suffix}"
  defp tenant(ctx), do: %{organization_id: ctx.organization.id, location_scope: :all}

  defp json_conn(conn, user),
    do: conn |> put_bearer_token(user) |> put_req_header("content-type", "application/json")

  defp day(ctx, offset), do: Date.add(Organizations.local_today(ctx.organization.id), offset)

  # The pre-ADR-680 shape: a root WOD given to a day leaves a filed copy.
  defp give_to_day(conn, ctx, workout, offset) do
    conn
    |> recycle()
    |> json_conn(ctx.admin)
    |> put(
      path("/admin/schedule/day-workouts"),
      Jason.encode!(%{date: day(ctx, offset), master_workout_id: workout.id})
    )
    |> json_response(200)
    |> Map.fetch!("day_workouts")
    |> hd()
    |> Map.fetch!("master_workout_id")
  end

  defp put_goals!(ctx, workout_id) do
    Repo.query!(
      """
      INSERT INTO workout_goals
        (id, organization_id, master_workout_id, qualities, taxonomy_version, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, $2, ARRAY['strength'], 1, now(), now())
      """,
      [Ecto.UUID.dump!(ctx.organization.id), Ecto.UUID.dump!(workout_id)]
    )
  end

  defp goals_of(workout_id) do
    Repo.query!("SELECT qualities FROM workout_goals WHERE master_workout_id = $1", [
      Ecto.UUID.dump!(workout_id)
    ]).rows
  end

  defp exists?(ctx, id), do: Workouts.get_workout_for_admin(tenant(ctx), id) != nil

  defp migrate! do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @version,
      @migration,
      :forward,
      :up,
      :up,
      log: false
    )
  end

  test "removes a root original filed once as a copy, moving its goals to the copy",
       %{conn: conn} = ctx do
    made_for_day = workout_fixture(ctx.admin, %{title: "Strength"})
    put_goals!(ctx, made_for_day.id)
    copy_id = give_to_day(conn, ctx, made_for_day, 2)
    refute copy_id == made_for_day.id

    # Templates: used twice, used by a class directly, edited after the copy.
    twice = workout_fixture(ctx.admin, %{title: "Used twice"})
    give_to_day(conn, ctx, twice, 3)
    give_to_day(conn, ctx, twice, 4)

    on_a_class = workout_fixture(ctx.admin, %{title: "On a class"})
    give_to_day(conn, ctx, on_a_class, 5)

    class_slot_fixture(ctx, on_a_class)

    edited = workout_fixture(ctx.admin, %{title: "Edited later"})
    give_to_day(conn, ctx, edited, 6)

    Repo.query!(
      "UPDATE master_workouts SET updated_at = updated_at + interval '1 hour' WHERE id = $1",
      [
        Ecto.UUID.dump!(edited.id)
      ]
    )

    migrate!()

    refute exists?(ctx, made_for_day.id)
    copy = Workouts.get_workout_for_admin(tenant(ctx), copy_id)
    assert copy.source_workout_id == nil
    assert goals_of(copy_id) == [[["strength"]]]

    assert exists?(ctx, twice.id)
    assert exists?(ctx, on_a_class.id)
    assert exists?(ctx, edited.id)
  end

  defp class_slot_fixture(ctx, workout) do
    scheduled_at =
      ctx
      |> day(7)
      |> DateTime.new!(~T[18:00:00], Organizations.organization_timezone(ctx.organization.id))
      |> DateTime.shift_zone!("Etc/UTC")

    {:ok, _slot} =
      Palee.Application.CreateScheduledSlot.call(tenant(ctx), %{
        class_type_id: ctx.crossfit.id,
        name: "CrossFit class",
        master_workout_id: workout.id,
        scheduled_at: scheduled_at,
        capacity: 10,
        auto_approve: true,
        booking_timeout_minutes: 30
      })
  end
end
