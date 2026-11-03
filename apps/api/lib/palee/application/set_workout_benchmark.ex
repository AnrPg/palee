defmodule Palee.Application.SetWorkoutBenchmark do
  @moduledoc """
  ADR-394: a coach tags a WOD as a known benchmark (Fran, Grace, a max
  back squat…) or clears the tag. Only a tagged WOD's results can rank on
  the Palee-wide board; the tag is never guessed from the title.
  """

  alias Palee.Workouts

  def call(context, workout_id, benchmark_key) do
    with {:ok, key} <- Workouts.normalize_benchmark_key(benchmark_key),
         {:ok, updated} <- Workouts.set_workout_benchmark(context, workout_id, key) do
      {:ok, present(updated)}
    end
  end

  @doc "The catalog the WOD editor's picker offers."
  def catalog do
    Enum.map(Workouts.benchmarks(), &Map.take(&1, [:key, :group, :unit, :lower_is_better]))
  end

  @doc "A benchmark as the API shows it, or nil."
  def present(%{benchmark_key: key} = workout) do
    %{id: workout.id, benchmark: describe(key)}
  end

  def describe(nil), do: nil

  def describe(key) do
    case Workouts.benchmark(key) do
      nil -> nil
      benchmark -> Map.take(benchmark, [:key, :group, :unit, :lower_is_better])
    end
  end
end
