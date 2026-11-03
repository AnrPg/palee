defmodule Palee.Workouts.Domain.WorkoutBenchmarksTest do
  @moduledoc "ADR-394: the benchmarks a coach can tag a WOD with."

  use ExUnit.Case, async: true

  alias Palee.Pantheon.Domain.FitnessBenchmarks
  alias Palee.Workouts.Domain.WorkoutBenchmarks

  @leaderboard_only ~w(annie jackie elizabeth nancy kelly angie barbara amanda murph dt)

  test "the 23 anchored benchmarks plus ten leaderboard-only WODs, each once" do
    keys = WorkoutBenchmarks.keys()

    assert length(keys) == 33
    assert keys == Enum.uniq(keys)
    assert Enum.take(keys, 23) == Enum.map(FitnessBenchmarks.all(), & &1.key)
    assert Enum.drop(keys, 23) == @leaderboard_only
  end

  test "the ten are for time and carry no fitness-profile anchors" do
    for key <- @leaderboard_only do
      benchmark = WorkoutBenchmarks.get(key)

      assert %{unit: "mins_secs", lower_is_better: true, group: "metcon"} = benchmark
      refute benchmark.fitness_profile
      refute Map.has_key?(benchmark, :anchors)
    end

    # The fitness profile's own catalog is untouched.
    assert length(FitnessBenchmarks.all()) == 23
    assert FitnessBenchmarks.match("murph") == nil
  end

  test "anchored benchmarks keep their unit, direction and domain" do
    assert %{unit: "kg", lower_is_better: false, group: "strength", fitness_profile: true} =
             WorkoutBenchmarks.get("back_squat")

    assert %{unit: "reps", lower_is_better: false} = WorkoutBenchmarks.get("cindy")
    assert %{unit: "mins_secs", lower_is_better: true} = WorkoutBenchmarks.get("fran")
  end

  test "aliases are kept in English and Greek, normalised" do
    assert "μερφ" in WorkoutBenchmarks.get("murph").aliases
    assert "murph" in WorkoutBenchmarks.get("murph").aliases
  end

  test "normalize/1 accepts a known key, clears on blank, refuses anything else" do
    assert {:ok, "fran"} = WorkoutBenchmarks.normalize(" fran ")
    assert {:ok, nil} = WorkoutBenchmarks.normalize(nil)
    assert {:ok, nil} = WorkoutBenchmarks.normalize("")
    assert {:error, :invalid_workout_benchmark} = WorkoutBenchmarks.normalize("Fran")
    assert {:error, :invalid_workout_benchmark} = WorkoutBenchmarks.normalize(42)
    assert WorkoutBenchmarks.get(nil) == nil
  end
end
