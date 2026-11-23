defmodule Palee.Application.ClassTimerView do
  @moduledoc """
  Loads a scheduled class with its timer and the segments the timer runs, and
  shapes the payload every screen (wall display, coach remote, member phone)
  renders. `server_now` lets clients correct for their own clock being off.

  `workout.body` is the workout in the shape it was written (ADR-224) for
  every authoring mode: each segment's `section_id` points at one of its
  sections, so a screen shows what is done now (the exercises of this
  minute, round or section, or the section's text) from the same payload.
  """

  alias Palee.{Execution, Scheduling, Workouts}
  alias Palee.Execution.Domain.{ClassTimerMachine, DurationAdjustments, TimerPresets}
  alias Palee.Scheduling.Domain.ClassWorkouts

  @free_text_timer_key "free_text_timer"

  @doc """
  Returns `{:ok, %{slot, workout, timer, base_segments, others}}` or
  `{:error, :not_found}`.

  ADR-746: a class may hold several WODs, each with its own timer.
  `workout_id` picks one of them (the coach remote, a member who chose a
  WOD); `nil` or any id the class does not have means the coach's «Τώρα»,
  which the wall display and box screens follow. `others` are the class's
  other timers, so a screen can show one that keeps running in the back.
  """
  def load(context, slot_id, workout_id \\ nil) do
    with {:ok, slot_id} <- Ecto.UUID.cast(slot_id),
         %{} = slot <- Scheduling.get_slot(context, slot_id) do
      selected =
        if ClassWorkouts.member?(slot, workout_id),
          do: workout_id,
          else: ClassWorkouts.live_id(slot)

      workout = selected && Workouts.get_workout(context, selected)
      timers = Execution.list_class_timers(context, slot_id)
      timer = Enum.find(timers, &(Map.get(&1, :master_workout_id) == selected))

      {:ok,
       %{
         slot: slot,
         workout: workout,
         timer: timer,
         base_segments: base_segments(workout, timer),
         others: Enum.reject(timers, &(Map.get(&1, :master_workout_id) == selected)),
         titles: workout_titles(context, slot, selected, workout)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "ADR-746: the WOD the view's timer runs (nil = a class without WOD)."
  def workout_id(%{workout: %{id: id}}), do: id
  def workout_id(_view), do: nil

  @doc """
  ADR-746: pushes the class's «Τώρα» timer to every screen following the
  class (after «Τώρα» changed or the list did).
  """
  def broadcast_current(context, slot_id) do
    with {:ok, view} <- load(context, slot_id) do
      broadcast(view.slot, payload(view, DateTime.utc_now()))
    end
  end

  @doc "Sends `payload` on the class's timer topic."
  def broadcast(slot, payload) do
    Phoenix.PubSub.broadcast(
      Palee.PubSub,
      "class_timer:updated",
      {:class_timer_updated,
       %{organization_id: slot.organization_id, scheduled_class_id: slot.id, payload: payload}}
    )
  end

  defp workout_titles(context, slot, selected, selected_workout) do
    Enum.map(ClassWorkouts.ids(slot), fn id ->
      workout = if id == selected, do: selected_workout, else: Workouts.get_workout(context, id)
      %{id: id, title: workout && workout.title}
    end)
  end

  @doc "Replaces the timer (after a save); its preset may change the segments."
  def with_timer(view, timer),
    do: %{view | timer: timer, base_segments: base_segments(view.workout, timer)}

  @doc "The timer as stored (or a fresh one), in machine form."
  def state(nil), do: ClassTimerMachine.initial()

  def state(timer) do
    %{
      status: timer.status,
      current_segment_index: timer.current_segment_index,
      segment_started_at_utc: timer.segment_started_at_utc,
      paused_elapsed_ms: timer.paused_elapsed_ms,
      duration_adjustments: timer.duration_adjustments || %{}
    }
  end

  def payload(%{slot: slot, workout: workout, timer: timer, base_segments: base} = view, now) do
    state = state(timer)
    live_id = ClassWorkouts.live_id(slot)
    selected_id = workout && workout.id
    segments = DurationAdjustments.apply_to(base, state.duration_adjustments)
    effective = ClassTimerMachine.catch_up(state, segments, now)

    %{
      class: %{
        id: slot.id,
        name: slot.name,
        scheduled_at: slot.scheduled_at,
        duration_minutes: slot.duration_minutes
      },
      workout:
        workout &&
          %{
            id: workout.id,
            title: workout.title,
            authoring_mode: Map.get(workout, :authoring_mode),
            free_text_body: Map.get(workout, :free_text_body),
            body: Map.get(workout, :body)
          },
      # ADR-746: every WOD of the class, the coach's «Τώρα», whether this
      # payload is the «Τώρα» timer (screens follow only that one), and the
      # class's other timers that run or wait paused.
      workouts: Map.get(view, :titles, []),
      live_workout_id: live_id,
      live: selected_id == live_id,
      other_timers: view |> Map.get(:others, []) |> Enum.map(&other_timer(&1, now)),
      segments: segments,
      timer:
        effective
        |> Map.merge(%{
          lock_version: (timer && timer.lock_version) || 1,
          timer_preset: timer && timer.timer_preset,
          updated_at: timer && timer.updated_at
        }),
      server_now: now
    }
  end

  defp other_timer(timer, _now) do
    %{
      workout_id: Map.get(timer, :master_workout_id),
      status: timer.status,
      current_segment_index: timer.current_segment_index,
      segment_started_at_utc: timer.segment_started_at_utc,
      paused_elapsed_ms: timer.paused_elapsed_ms
    }
  end

  # A timer the coach picked for this class wins (e.g. an EMOM clock for an
  # untimed strength class). Otherwise structured workouts run their own
  # sequence, and free-text ones the preset attached to the workout.
  defp base_segments(workout, timer) do
    case TimerPresets.parse(timer && timer.timer_preset) do
      %{} = preset ->
        TimerPresets.build(preset)

      nil ->
        workout_segments(workout && Map.get(workout, :authoring_mode), workout)
    end
  end

  # ADR-180: a workout written in text sections runs each section's own timer.
  defp workout_segments("sectioned_text", workout),
    do: TimerPresets.build_sections(Map.get(workout, :sections) || [])

  defp workout_segments(mode, workout) do
    structured =
      if workout && mode != "free_text",
        do: Execution.build_timer_sequence(workout),
        else: []

    case {structured, TimerPresets.parse(workout_preset(workout))} do
      {[_ | _], _preset} -> structured
      {[], %{} = preset} -> TimerPresets.build(preset)
      {[], nil} -> []
    end
  end

  defp workout_preset(nil), do: nil

  defp workout_preset(workout) do
    case Map.get(workout, :workout_metadata) do
      %{} = metadata -> Map.get(metadata, @free_text_timer_key)
      _ -> nil
    end
  end
end
