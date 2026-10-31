defmodule Palee.Workouts.Domain.WorkoutSnapshotTest do
  use ExUnit.Case, async: true

  alias Palee.Scheduling.Domain.DayAssignmentTag
  alias Palee.Workouts.Domain.WorkoutSnapshot

  @workout %{
    id: "w1",
    organization_id: "o1",
    folder_id: "f1",
    status: "published",
    title: "Fran",
    type: "crossfit",
    inserted_at: ~U[2026-10-01 10:00:00Z],
    updated_at: ~U[2026-10-02 10:00:00Z],
    sections: [
      %{
        id: "s1",
        name: "For time",
        workout_id: "w1",
        inserted_at: ~U[2026-10-01 10:00:00Z],
        exercises: [%{id: "e1", name: "Thrusters", prescription_value: 21}]
      }
    ]
  }

  test "keeps what the WOD says, drops where it is kept" do
    content = WorkoutSnapshot.content(@workout)

    assert content["title"] == "Fran"
    refute Map.has_key?(content, "id")
    refute Map.has_key?(content, "folder_id")
    refute Map.has_key?(content, "status")
    refute Map.has_key?(content, "updated_at")

    assert [%{"id" => "s1", "name" => "For time", "exercises" => [%{"name" => "Thrusters"}]}] =
             content["sections"]

    refute Map.has_key?(hd(content["sections"]), "workout_id")
  end

  test "the hash ignores bookkeeping and changes with the content" do
    moved = %{@workout | folder_id: "f2", updated_at: ~U[2026-10-30 10:00:00Z]}
    edited = put_in(@workout, [:sections, Access.at(0), :exercises], [%{name: "Thrusters", prescription_value: 15}])

    base = @workout |> WorkoutSnapshot.content() |> WorkoutSnapshot.hash()

    assert base == moved |> WorkoutSnapshot.content() |> WorkoutSnapshot.hash()
    refute base == edited |> WorkoutSnapshot.content() |> WorkoutSnapshot.hash()
    assert String.length(base) == 64
  end

  test "build/1 and same?/2" do
    snapshot = WorkoutSnapshot.build(@workout)
    assert %{title: "Fran", format_version: 1, content_hash: hash} = snapshot
    assert WorkoutSnapshot.same?(%{content_hash: hash}, @workout)
    refute WorkoutSnapshot.same?(%{content_hash: hash}, %{@workout | title: "Fran (heavy)"})
  end

  describe "DayAssignmentTag" do
    test "tags a day by its live classes" do
      wod = %{master_workout_id: "w"}
      none = %{master_workout_id: nil}
      cancelled = %{master_workout_id: nil, cancelled_at: ~U[2026-10-31 08:00:00Z]}

      assert %{tag: "none", classes: 0} = DayAssignmentTag.tag([])
      assert %{tag: "not_assigned", classes: 2} = DayAssignmentTag.tag([none, none])
      assert %{tag: "mixed", classes: 2, with_wod: 1} = DayAssignmentTag.tag([wod, none])
      assert %{tag: "all_assigned"} = DayAssignmentTag.tag([wod, wod, cancelled])
      assert %{tag: "none"} = DayAssignmentTag.tag([cancelled])
    end

    test "by_day/2 gives every date of the range, in order" do
      classes = [
        %{local_date: ~D[2026-11-02], master_workout_id: "w"},
        %{local_date: ~D[2026-11-02], master_workout_id: nil}
      ]

      assert [
               %{date: ~D[2026-11-01], tag: "none"},
               %{date: ~D[2026-11-02], tag: "mixed"}
             ] = DayAssignmentTag.by_day([~D[2026-11-01], ~D[2026-11-02]], classes)
    end
  end
end
