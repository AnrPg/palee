defmodule Palee.Application.ClassProgrammeLoadTest do
  @moduledoc """
  ADR-670 «Φορτίο προγράμματος»: the muscle groups the same class (class
  type and branch) worked in the 7 gym days before a class, each WOD once
  per day, with saved goals or else the suggestion from its exercises.
  """
  use Palee.DataCase, async: false

  import Palee.AnalyticsHelpers

  alias Palee.Application.{GetClassProgrammeLoad, SaveWorkoutGoals}
  alias Palee.Scheduling.ScheduledClass
  alias Palee.TestFixtures

  setup do
    {org, owner, staff} = organization_fixture()
    crossfit = TestFixtures.class_type_fixture(%{tenant_context: staff, name: "CrossFit"})
    yoga = TestFixtures.class_type_fixture(%{tenant_context: staff, name: "Yoga"})

    squats = TestFixtures.workout_fixture(owner, %{tenant_context: staff})
    pulls = TestFixtures.workout_fixture(owner, %{tenant_context: staff})
    today = TestFixtures.workout_fixture(owner, %{tenant_context: staff})

    {:ok, _} =
      SaveWorkoutGoals.call(staff, squats.id, %{
        "muscles" => [
          %{"id" => "quadriceps", "role" => "primary"},
          %{"id" => "gluteus-maximus", "role" => "secondary"}
        ]
      })

    {:ok, _} =
      SaveWorkoutGoals.call(staff, pulls.id, %{
        "muscles" => [
          %{"id" => "latissimus-dorsi", "role" => "primary"},
          %{"id" => "quadriceps", "role" => "stabilizer"}
        ]
      })

    %{
      org: org,
      staff: staff,
      crossfit: crossfit,
      yoga: yoga,
      squats: squats,
      pulls: pulls,
      today: today
    }
  end

  # A class at `at` (created in the future, then moved, so past times work).
  defp class!(ctx, workout, class_type, at, set \\ []) do
    slot =
      TestFixtures.slot_fixture(workout, %{
        tenant_context: ctx.staff,
        class_type_id: class_type.id
      })

    {1, _} =
      ScheduledClass
      |> where([class], class.id == ^slot.id)
      |> Repo.update_all(set: [scheduled_at: at] ++ set)

    slot
  end

  test "counts the same class's WODs of the previous 7 days, each once per day", ctx do
    target_at = ~U[2026-11-19 16:00:00Z]
    day = fn days_before, hour -> DateTime.add(target_at, -days_before * 86_400 + hour * 3600) end

    target = class!(ctx, ctx.today, ctx.crossfit, target_at)
    # Two classes on the same day with the same WOD count once.
    class!(ctx, ctx.squats, ctx.crossfit, day.(1, 0))
    class!(ctx, ctx.squats, ctx.crossfit, day.(1, 1))
    class!(ctx, ctx.pulls, ctx.crossfit, day.(3, 0))
    # Another class type, a cancelled class, too old and a later class: left out.
    class!(ctx, ctx.pulls, ctx.yoga, day.(2, 0))

    class!(ctx, ctx.pulls, ctx.crossfit, day.(2, 0),
      cancelled_at: DateTime.add(target_at, -86_400 * 3)
    )

    class!(ctx, ctx.squats, ctx.crossfit, day.(9, 0))
    class!(ctx, ctx.squats, ctx.crossfit, day.(-1, 0))

    assert {:ok, load} = GetClassProgrammeLoad.call(ctx.staff, target.id)
    assert load.scheduled_class_id == target.id
    assert load.days == 7
    assert load.wods == 2
    assert Date.diff(load.to, load.from) == 6

    assert [
             %{id: "quadriceps", wods: 2, primary: 1, stabilizer: 1},
             %{id: "latissimus-dorsi", wods: 1, primary: 1},
             %{id: "glutes", wods: 1, secondary: 1}
           ] = load.muscles
  end

  test "an unknown or malformed class is not found", ctx do
    assert {:error, :not_found} = GetClassProgrammeLoad.call(ctx.staff, Ecto.UUID.generate())
    assert {:error, :not_found} = GetClassProgrammeLoad.call(ctx.staff, "nope")
  end
end
