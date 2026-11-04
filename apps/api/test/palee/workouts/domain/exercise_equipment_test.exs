defmodule Palee.Workouts.Domain.ExerciseEquipmentTest do
  @moduledoc "ADR-542: the equipment of the canonical exercise catalogue."
  use ExUnit.Case, async: true

  alias Palee.Workouts
  alias Palee.Workouts.Domain.ExerciseEquipment
  alias Palee.Workouts.Domain.WorkoutDsl.{ExerciseCatalog, Vocabulary}

  test "every mapped exercise is a catalogue entry and every key is in the vocabulary" do
    catalogue = MapSet.new(ExerciseCatalog.entries(), & &1.id)

    for {id, keys} <- ExerciseEquipment.export() do
      assert MapSet.member?(catalogue, id), "#{id} is not in the catalogue"
      assert keys != []
      assert Enum.all?(keys, &ExerciseEquipment.key?/1), "#{id}: #{inspect(keys)}"
      assert keys == ["none"] or "none" not in keys
    end
  end

  test "ambiguous or unlisted exercises are unknown, never `none`" do
    assert ExerciseEquipment.for_exercise("back-squat") == ["barbell"]
    assert ExerciseEquipment.for_exercise("burpee") == ["none"]
    assert ExerciseEquipment.for_exercise("goblet-squat") == :unknown
    assert ExerciseEquipment.for_exercise("lunge") == :unknown
    assert ExerciseEquipment.for_exercise("not-an-exercise") == :unknown
    assert ExerciseEquipment.for_exercise(nil) == :unknown
  end

  test "the WOD editor's vocabulary carries the equipment beside the catalogue" do
    vocabulary = Vocabulary.export()
    assert vocabulary.equipment_keys == ExerciseEquipment.keys()
    assert vocabulary.exercise_equipment["row"] == ["rower"]
    refute Map.has_key?(vocabulary.exercise_equipment, "goblet-squat")
  end

  test "a WOD's equipment comes from its exercises, by ref or by name" do
    workout = %{
      sections: [
        %{
          exercises: [
            %{name: "Thruster", exercise_ref: "thruster", sets: 3},
            %{name: "Pull-ups"},
            %{name: "Burpees"},
            %{name: "Goblet squat"},
            %{name: "Partner carry relay"}
          ]
        }
      ]
    }

    assert %{equipment: ["barbell", "pull_up_bar"], unknown: 2} =
             Workouts.workout_equipment(workout)

    assert %{equipment: ["none"], unknown: 0} =
             Workouts.workout_equipment(%{free_text_body: "50 burpees\n100 air squats"})

    assert %{equipment: [], unknown: 0} = Workouts.workout_equipment(%{})
  end
end
