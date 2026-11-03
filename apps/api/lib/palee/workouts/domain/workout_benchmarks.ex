defmodule Palee.Workouts.Domain.WorkoutBenchmarks do
  @moduledoc """
  ADR-394: the benchmarks a coach can tag a box WOD with, so its results
  also rank on the Palee-wide board («Όλο το Palee»).

  The list is the 23 anchored benchmarks of the fitness profile
  (`Pantheon.Domain.FitnessBenchmarks`, ADR-358) plus ten well-known
  benchmark WODs that exist only for the leaderboard (ANR 2026-11-03):
  Annie, Jackie, Elizabeth, Nancy, Kelly, Angie, Barbara, Amanda, Murph and
  DT, all for time. The ten carry no fitness-profile anchors and never
  change the profile: `FitnessBenchmarks` stays the profile's own catalog.
  Murph with or without a vest is a scale level, not another benchmark.

  Each entry: `key`, `group` (the fitness domain, or `metcon` for the ten),
  `unit` (`kg`, `reps`, `mins_secs`), `lower_is_better` and `aliases` (EN
  and EL, normalised). The tag is always the coach's choice; a WOD is never
  matched by its title.
  """

  alias Palee.Pantheon.Domain.FitnessBenchmarks

  # {key, aliases in English and Greek}: every one for time.
  @leaderboard_only [
    {"annie", ["annie", "άνι"]},
    {"jackie", ["jackie", "τζάκι"]},
    {"elizabeth", ["elizabeth", "ελίζαμπεθ"]},
    {"nancy", ["nancy", "νάνσι"]},
    {"kelly", ["kelly", "κέλι"]},
    {"angie", ["angie", "άντζι"]},
    {"barbara", ["barbara", "μπάρμπαρα"]},
    {"amanda", ["amanda", "αμάντα"]},
    {"murph", ["murph", "μερφ"]},
    {"dt", ["dt", "d.t.", "ντι τι"]}
  ]

  @doc "Every benchmark a coach can pick, the anchored ones first."
  def all do
    anchored =
      Enum.map(FitnessBenchmarks.all(), fn benchmark ->
        benchmark
        |> Map.take([:key, :unit, :lower_is_better, :aliases])
        |> Map.put(:group, benchmark.domain)
        |> Map.put(:fitness_profile, true)
      end)

    extra =
      Enum.map(@leaderboard_only, fn {key, aliases} ->
        %{
          key: key,
          group: "metcon",
          unit: "mins_secs",
          lower_is_better: true,
          aliases: Enum.map(aliases, &FitnessBenchmarks.normalize/1),
          fitness_profile: false
        }
      end)

    anchored ++ extra
  end

  @doc "The keys, in catalog order."
  def keys, do: Enum.map(all(), & &1.key)

  @doc "The benchmark of a key, or nil."
  def get(key) when is_binary(key), do: Enum.find(all(), &(&1.key == key))
  def get(_key), do: nil

  @doc """
  `{:ok, key | nil}` for a key the catalog knows (blank clears the tag),
  `{:error, :invalid_workout_benchmark}` otherwise.
  """
  def normalize(nil), do: {:ok, nil}

  def normalize(key) when is_binary(key) do
    case String.trim(key) do
      "" -> {:ok, nil}
      trimmed -> if get(trimmed), do: {:ok, trimmed}, else: {:error, :invalid_workout_benchmark}
    end
  end

  def normalize(_key), do: {:error, :invalid_workout_benchmark}
end
