defmodule Palee.Scheduling.Domain.ClassWorkoutsTest do
  use ExUnit.Case, async: true

  alias Palee.Scheduling.Domain.ClassWorkouts

  @a "00000000-0000-0000-0000-00000000000a"
  @b "00000000-0000-0000-0000-00000000000b"
  @c "00000000-0000-0000-0000-00000000000c"

  defp slot(attrs \\ %{}),
    do: Map.merge(%{master_workout_id: @a, additional_workout_ids: [@b, @c]}, attrs)

  describe "ids/1" do
    test "the first WOD, then the rest in order" do
      assert ClassWorkouts.ids(slot()) == [@a, @b, @c]
    end

    test "drops gaps and repeats" do
      assert ClassWorkouts.ids(%{master_workout_id: nil, additional_workout_ids: [@b, @b]}) == [
               @b
             ]

      assert ClassWorkouts.ids(%{master_workout_id: @a}) == [@a]
      assert ClassWorkouts.ids(%{master_workout_id: nil}) == []
    end
  end

  test "multiple?/1" do
    assert ClassWorkouts.multiple?(slot())
    refute ClassWorkouts.multiple?(%{master_workout_id: @a, additional_workout_ids: []})
  end

  describe "live_id/1" do
    test "the coach's pointer when the class has that WOD" do
      assert ClassWorkouts.live_id(slot(%{live_workout_id: @b})) == @b
    end

    test "falls back to the first WOD" do
      assert ClassWorkouts.live_id(slot(%{live_workout_id: nil})) == @a
      assert ClassWorkouts.live_id(slot(%{live_workout_id: "gone"})) == @a
      assert ClassWorkouts.live_id(%{master_workout_id: nil}) == nil
    end
  end

  describe "effective_id/2" do
    test "the person's choice, else the coach's «Τώρα»" do
      live = slot(%{live_workout_id: @b})
      assert ClassWorkouts.effective_id(%{chosen_workout_id: @c}, live) == @c
      assert ClassWorkouts.effective_id(%{chosen_workout_id: nil}, live) == @b
      assert ClassWorkouts.effective_id(%{chosen_workout_id: "removed"}, live) == @b
      assert ClassWorkouts.effective_id(nil, live) == @b
    end
  end

  describe "validate_list/1" do
    test "accepts unique ids and an empty list" do
      assert ClassWorkouts.validate_list([@a, @b]) == :ok
      assert ClassWorkouts.validate_list([]) == :ok
    end

    test "refuses repeats and non-lists" do
      assert ClassWorkouts.validate_list([@a, @a]) == {:error, :duplicate_class_workout}
      assert ClassWorkouts.validate_list([@a, 1]) == {:error, :invalid_class_workouts}
      assert ClassWorkouts.validate_list(nil) == {:error, :invalid_class_workouts}
    end
  end

  test "after_change/3 resets pointers that named a removed WOD" do
    bookings = [
      %{id: "keep", chosen_workout_id: @a},
      %{id: "clear", chosen_workout_id: @c},
      %{id: "undecided", chosen_workout_id: nil}
    ]

    assert ClassWorkouts.after_change(%{live_workout_id: @c}, [@a, @b], bookings) == %{
             live_reset?: true,
             cleared_booking_ids: ["clear"]
           }

    assert %{live_reset?: false} = ClassWorkouts.after_change(%{live_workout_id: nil}, [@a], [])
  end

  test "choice_counts/2 counts active member bookings only; seats stay shared" do
    bookings = [
      %{status: :approved, chosen_workout_id: @a, guest_name: nil},
      %{status: :approved, chosen_workout_id: @a, guest_name: nil},
      %{status: :pending, chosen_workout_id: @b, guest_name: nil},
      %{status: :approved, chosen_workout_id: nil, guest_name: nil},
      %{status: :approved, chosen_workout_id: "removed", guest_name: nil},
      %{status: :cancelled, chosen_workout_id: @a, guest_name: nil},
      %{status: :approved, chosen_workout_id: nil, guest_name: "Guest"}
    ]

    assert ClassWorkouts.choice_counts(slot(), bookings) == %{
             workouts: %{@a => 2, @b => 1, @c => 0},
             undecided: 2
           }
  end
end
