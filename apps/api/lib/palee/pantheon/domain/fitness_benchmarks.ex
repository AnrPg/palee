defmodule Palee.Pantheon.Domain.FitnessBenchmarks do
  @moduledoc """
  ADR-358 (CP-D6): the benchmarks the fitness profile reads, version 1.

  Each benchmark belongs to one domain and says how its PR is read:

    * `unit` – the PR unit it accepts (`kg`, `reps`, `mins_secs`; a time is
      in seconds and lower is better);
    * `anchors` – per division (`women`, `men`), four `{value, points}`
      pairs (20, 50, 75, 95). Points between anchors are interpolated
      linearly; below the first anchor they fall towards 0, above the last
      they are capped at 100. Without a division the mean of the two is
      used, and the profile says so.

  The anchors are coarse population standards for adults who train in a
  box (roughly: 20 «started», 50 «trained», 75 «strong club athlete»,
  95 «competitive»). They are part of the algorithm version: changing a
  number is a new version (`FitnessProfile.algorithm/0`), never an edit.

  PR names match by `aliases` after `normalize/1` (lower case, accents and
  punctuation dropped), in English and Greek.
  """

  @domains ~w(strength power gymnastics monostructural metcon)

  # NEEDS COACH REVIEW (ANR 2026-11-02, mockup d6): every anchor below is a
  # generic population value that a pilot coach has not checked yet. The
  # Πρόοδος card shows these numbers to members; a reviewed set is a new
  # algorithm version, never an edit of this one.
  #
  # {key, domain, unit, aliases, women anchors, men anchors}
  @catalog [
    {"back_squat", "strength", "kg", ["back squat", "squat", "πισω καθισμα", "καθισμα"],
     [40, 65, 95, 125], [60, 100, 140, 180]},
    {"front_squat", "strength", "kg", ["front squat", "μπροστινο καθισμα"], [35, 55, 80, 105],
     [50, 85, 120, 155]},
    {"deadlift", "strength", "kg", ["deadlift", "dead lift", "ασκηση θανατου", "νεκρη αρση"],
     [50, 85, 120, 160], [80, 130, 180, 230]},
    {"bench_press", "strength", "kg", ["bench press", "bench", "πιεσεις παγκου"],
     [30, 45, 65, 85], [50, 80, 110, 140]},
    {"strict_press", "strength", "kg",
     ["strict press", "shoulder press", "press", "overhead press", "military press"],
     [20, 35, 48, 62], [35, 55, 75, 95]},
    {"clean", "power", "kg",
     ["clean", "power clean", "squat clean", "clean and jerk", "clean & jerk", "clean jerk"],
     [35, 55, 75, 95], [50, 80, 110, 140]},
    {"snatch", "power", "kg", ["snatch", "power snatch", "squat snatch", "αρπαγη"],
     [25, 45, 60, 80], [40, 65, 90, 115]},
    {"pull_ups", "gymnastics", "reps",
     ["pull ups", "pull up", "pullups", "pullup", "kipping pull ups", "ελξεις", "μονοζυγο"],
     [1, 6, 15, 28], [3, 12, 25, 40]},
    {"handstand_push_ups", "gymnastics", "reps",
     ["handstand push ups", "handstand push up", "hspu", "κατακορυφες καμψεις"], [1, 4, 12, 25],
     [1, 8, 20, 35]},
    {"muscle_ups", "gymnastics", "reps",
     [
       "muscle ups",
       "muscle up",
       "bar muscle ups",
       "bar muscle up",
       "ring muscle ups",
       "ring muscle up"
     ], [1, 2, 6, 12], [1, 4, 10, 20]},
    {"toes_to_bar", "gymnastics", "reps", ["toes to bar", "t2b", "ttb"], [2, 12, 25, 45],
     [3, 15, 30, 50]},
    {"push_ups", "gymnastics", "reps", ["push ups", "push up", "pushups", "καμψεις"],
     [5, 20, 35, 50], [10, 30, 50, 70]},
    {"row_500m", "monostructural", "mins_secs", ["500m row", "row 500m", "500 m row", "κωπη 500"],
     [140, 120, 110, 100], [120, 105, 95, 88]},
    {"row_2k", "monostructural", "mins_secs",
     ["2k row", "2000m row", "row 2k", "row 2000m", "κωπη 2000"], [560, 500, 465, 440],
     [480, 430, 400, 380]},
    {"run_1_mile", "monostructural", "mins_secs", ["1 mile run", "mile run", "mile", "1 mile"],
     [700, 520, 440, 390], [600, 450, 380, 330]},
    {"run_5k", "monostructural", "mins_secs", ["5k run", "5k", "5km run", "5 km", "τρεξιμο 5km"],
     [2100, 1740, 1470, 1300], [1800, 1500, 1260, 1110]},
    {"fran", "metcon", "mins_secs", ["fran"], [720, 420, 300, 190], [600, 360, 240, 150]},
    {"grace", "metcon", "mins_secs", ["grace"], [480, 300, 180, 120], [420, 240, 150, 100]},
    {"helen", "metcon", "mins_secs", ["helen"], [1020, 780, 640, 560], [900, 690, 570, 500]},
    {"diane", "metcon", "mins_secs", ["diane"], [1020, 660, 420, 260], [900, 540, 330, 200]},
    {"isabel", "metcon", "mins_secs", ["isabel"], [540, 330, 200, 130], [480, 270, 165, 105]},
    {"karen", "metcon", "mins_secs", ["karen"], [1020, 690, 510, 420], [900, 600, 450, 360]},
    {"cindy", "metcon", "reps", ["cindy"], [8, 15, 20, 25], [10, 17, 22, 27]}
  ]

  @points [20, 50, 75, 95]

  def domains, do: @domains

  @doc "Every benchmark: `%{key, domain, unit, lower_is_better, anchors: %{women, men, neutral}}`."
  def all, do: Enum.map(@catalog, &entry/1)

  @doc "The benchmark a PR name stands for, or nil."
  def match(name) when is_binary(name) do
    wanted = normalize(name)
    Enum.find(all(), fn benchmark -> wanted in benchmark.aliases end)
  end

  def match(_name), do: nil

  @doc "Lower case, no accents, no punctuation, single spaces."
  def normalize(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^\p{L}\p{N}&]+/u, " ")
    |> String.trim()
  end

  defp entry({key, domain, unit, aliases, women, men}) do
    %{
      key: key,
      domain: domain,
      unit: unit,
      lower_is_better: unit == "mins_secs",
      aliases: Enum.map(aliases, &normalize/1),
      anchors: %{
        "women" => Enum.zip(women, @points),
        "men" => Enum.zip(men, @points),
        nil => Enum.zip(Enum.zip_with(women, men, &((&1 + &2) / 2)), @points)
      }
    }
  end
end
