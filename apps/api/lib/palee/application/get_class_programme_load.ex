defmodule Palee.Application.GetClassProgrammeLoad do
  @moduledoc """
  `GET /api/org/:slug/admin/schedule/slots/:id/programme-load` (ADR-670,
  «Φορτίο προγράμματος»): which muscle groups the same class already
  worked in the 7 days before this one, so a coach sees whether the WOD
  loads the same muscles again.

  "The same class" is every class of the same class type at the same
  branch (ADR-186); cancelled classes and classes without a WOD are left
  out. Each class's WOD counts once per gym day (ADR-176), with its goals:
  the saved or inherited ones, else the live suggestion from its exercises
  (as staff see them in the goals sheet). Only the programme is read: no
  booking, result or journal entry of any member.
  """

  alias Palee.Application.WorkoutGoalsPresenter, as: Presenter
  alias Palee.{Anatomy, Organizations, Scheduling, Workouts}
  alias Palee.Scheduling.DayWorkoutStore
  alias Palee.TimeZones.ZonedTime

  @days 7

  def days, do: @days

  def call(context, slot_id) do
    with {:ok, slot_id} <- cast_id(slot_id),
         %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- Organizations.authorize_location(context, Map.get(slot, :location_id)) do
      {:ok, build(context, slot)}
    end
  end

  defp build(context, slot) do
    zone = Organizations.organization_timezone(context.organization_id)
    day = ZonedTime.local_date(slot.scheduled_at, zone)
    from_day = Date.add(day, -@days)
    window_start = ZonedTime.start_of_day(from_day, zone)

    wods =
      context
      |> DayWorkoutStore.list_classes(window_start, slot.scheduled_at)
      |> Enum.filter(&same_class?(&1, slot))
      |> Enum.map(&{ZonedTime.local_date(&1.scheduled_at, zone), &1.master_workout_id})
      |> Enum.uniq()

    goals = goals_by_workout(context, wods |> Enum.map(&elem(&1, 1)) |> Enum.uniq())

    %{
      scheduled_class_id: slot.id,
      days: @days,
      from: from_day,
      to: Date.add(day, -1),
      wods: length(wods),
      muscles:
        wods
        |> Enum.map(fn {on, workout_id} -> %{on: on, muscles: Map.get(goals, workout_id, [])} end)
        |> Anatomy.programme_load()
    }
  end

  defp same_class?(class, slot) do
    class.id != slot.id and is_nil(class.cancelled_at) and is_binary(class.master_workout_id) and
      class.class_type_id == slot.class_type_id and
      class.location_id == Map.get(slot, :location_id)
  end

  defp goals_by_workout(context, workout_ids) do
    Map.new(workout_ids, fn workout_id -> {workout_id, goal_muscles(context, workout_id)} end)
  end

  defp goal_muscles(context, workout_id) do
    case Workouts.resolve_workout_goals(context, workout_id) do
      %{goals: %{muscles: muscles}} ->
        Enum.map(muscles, &Presenter.muscle/1)

      _none ->
        case Workouts.get_workout_for_admin(context, workout_id) do
          %{} = workout -> Presenter.suggestion(workout).muscles
          _missing -> []
        end
    end
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
