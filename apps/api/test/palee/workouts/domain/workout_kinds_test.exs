defmodule Palee.Workouts.Domain.WorkoutKindsTest do
  @moduledoc "ADR-690: workout type references, families and the box catalogue."

  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.WorkoutKinds

  @box_id "4f1c2b7e-1d2c-4a1b-9c3d-2e1f0a9b8c7d"
  @other_id "5a2d3c8f-2e3d-4b2c-8d4e-3f2a1b0c9d8e"
  @box_ref "box:" <> @box_id
  @other_ref "box:" <> @other_id

  @catalogue %{
    additions: [%{key: "animal_flow", family: "mind_body"}],
    box: [
      %{id: @box_id, label: "Engine", family: "endurance", status: "active", merged_into: nil},
      %{
        id: @other_id,
        label: "Old",
        family: "strength",
        status: "merged",
        merged_into: "crossfit"
      }
    ]
  }

  test "labels fold without accents, case or extra spaces" do
    assert WorkoutKinds.fold("  Ζώνη   ΤΑΧΥΤΗΤΑΣ ") == "ζωνη ταχυτητασ"
    assert {:ok, "Hyrox Sim"} = WorkoutKinds.label("  Hyrox   Sim ")
    assert {:error, :workout_kind_label_too_short} = WorkoutKinds.label("x")
    assert {:error, :workout_kind_label_too_long} = WorkoutKinds.label(String.duplicate("a", 41))
  end

  test "every reference has a family; a merged box type follows its target" do
    assert WorkoutKinds.family("strength", @catalogue) == "strength"
    assert WorkoutKinds.family("animal_flow", @catalogue) == "mind_body"
    assert WorkoutKinds.family(@box_ref, @catalogue) == "endurance"
    assert WorkoutKinds.family(@other_ref, @catalogue) == "functional"
    assert WorkoutKinds.family("nothing_like_it", @catalogue) == nil
  end

  test "families come once each, in catalogue order" do
    assert WorkoutKinds.families([@box_ref, "crossfit", "hyrox", "strength"], @catalogue) ==
             ["functional", "strength", "endurance"]
  end

  test "normalize keeps known references, sorted, and names the unknown ones" do
    assert {:ok, ["hyrox", "strength", "animal_flow", @box_ref]} =
             WorkoutKinds.normalize(
               [@box_ref, "strength", "animal_flow", "hyrox", "strength"],
               @catalogue
             )

    unknown = "box:" <> Ecto.UUID.generate()

    assert {:error, {:unknown_workout_types, [^unknown]}} =
             WorkoutKinds.normalize([unknown], @catalogue)
  end

  test "the compatibility type is the first built-in kind, or nil" do
    assert WorkoutKinds.legacy_type(["hyrox", "strength"]) == "hyrox"
    assert WorkoutKinds.legacy_type([@box_ref]) == nil
  end

  test "a sectioned WOD's types are its sections' union, else its own types" do
    assert WorkoutKinds.requested(["yoga"], nil, [["strength"], [@box_ref, "strength"]])
           |> Enum.sort() ==
             Enum.sort(["strength", @box_ref])

    assert WorkoutKinds.requested(["yoga"], "crossfit", [[], []]) == ["yoga"]
    assert WorkoutKinds.requested(nil, "crossfit", []) == ["crossfit"]
  end

  test "rewrite replaces a type once, keeping the others" do
    assert WorkoutKinds.rewrite([@box_ref, "crossfit"], @box_ref, "crossfit", @catalogue) == [
             "crossfit"
           ]

    assert WorkoutKinds.rewrite([@box_ref, "yoga"], @box_ref, "running", @catalogue) == [
             "running",
             "yoga"
           ]
  end
end
