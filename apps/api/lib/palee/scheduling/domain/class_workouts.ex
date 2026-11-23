defmodule Palee.Scheduling.Domain.ClassWorkouts do
  @moduledoc """
  The WODs of one class (ADR-746). Pure.

  A class holds an ordered list of WODs: the first is
  `master_workout_id` (what every older reader calls "the class's WOD"),
  the rest `additional_workout_ids`. The coach points at one as «Τώρα»
  (`live_workout_id`, nil = the first); the class timer and box screens
  follow it. Each booking may name the WOD its person does
  (`chosen_workout_id`); nil means «Θα αποφασίσω στο box»: the person
  follows the coach's «Τώρα».

  Seats are the class's, never a WOD's: the list changes nothing about
  capacity, waitlists, approvals or credits.

  Every reader goes through `ids/1`, `live_id/1` and `effective_id/2`, so a
  stale pointer (a WOD removed from the list) falls back instead of
  pointing at a WOD the class no longer has.
  """

  @active_statuses [:pending, :approved, "pending", "approved"]

  @doc "The class's WODs in order, without gaps or repeats."
  def ids(slot) do
    [Map.get(slot, :master_workout_id) | Map.get(slot, :additional_workout_ids) || []]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc "Whether the class has more than one WOD."
  def multiple?(slot), do: match?([_, _ | _], ids(slot))

  @doc "Whether `workout_id` is one of the class's WODs."
  def member?(slot, workout_id), do: is_binary(workout_id) and workout_id in ids(slot)

  @doc "The coach's «Τώρα»: the pointer when it is one of the WODs, else the first."
  def live_id(slot) do
    live = Map.get(slot, :live_workout_id)
    if member?(slot, live), do: live, else: List.first(ids(slot))
  end

  @doc "The WOD a booking chose, when the class still has it (nil = undecided)."
  def chosen_id(booking, slot) do
    chosen = booking && Map.get(booking, :chosen_workout_id)
    if member?(slot, chosen), do: chosen, else: nil
  end

  @doc "The WOD the booking's person does now: their choice, else the coach's «Τώρα»."
  def effective_id(booking, slot), do: chosen_id(booking, slot) || live_id(slot)

  @doc """
  Checks a new ordered list for a class: unique ids. An empty list removes
  every WOD (the class becomes a draft, which a booked class refuses
  elsewhere).
  """
  def validate_list(ids) when is_list(ids) do
    cond do
      not Enum.all?(ids, &is_binary/1) -> {:error, :invalid_class_workouts}
      length(Enum.uniq(ids)) != length(ids) -> {:error, :duplicate_class_workout}
      true -> :ok
    end
  end

  def validate_list(_ids), do: {:error, :invalid_class_workouts}

  @doc """
  What a new list means for the pointers that named a removed WOD:
  `live_reset?` when «Τώρα» must go back to the first, and the bookings
  whose choice must go back to «Θα αποφασίσω στο box».
  """
  def after_change(slot, new_ids, bookings) do
    live = Map.get(slot, :live_workout_id)

    %{
      live_reset?: is_binary(live) and live not in new_ids,
      cleared_booking_ids:
        bookings
        |> Enum.filter(fn booking ->
          chosen = Map.get(booking, :chosen_workout_id)
          is_binary(chosen) and chosen not in new_ids
        end)
        |> Enum.map(& &1.id)
    }
  end

  @doc """
  How many active bookings do each WOD: `%{workout_id => n}` for every WOD
  of the class, and `undecided` for those who will decide at the box.
  """
  def choice_counts(slot, bookings) do
    active =
      Enum.filter(bookings, fn booking ->
        Map.get(booking, :status) in @active_statuses and is_nil(Map.get(booking, :guest_name))
      end)

    by_workout =
      active
      |> Enum.map(&chosen_id(&1, slot))
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    %{
      workouts: Map.new(ids(slot), &{&1, Map.get(by_workout, &1, 0)}),
      undecided: Enum.count(active, &is_nil(chosen_id(&1, slot)))
    }
  end
end
