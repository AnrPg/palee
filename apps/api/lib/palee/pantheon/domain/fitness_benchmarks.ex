defmodule Palee.Pantheon.Domain.FitnessBenchmarks do
  @moduledoc """
  ADR-358 (CP-D6): the benchmarks the fitness profile reads. Version 2
  (ADR-395) adds the lifts' anchors as a multiple of body weight
  (`ratio_anchors`) and the age bands' percentages (`age_factor/2`).

  Each benchmark belongs to one domain and says how its PR is read:

    * `unit` – the PR unit it accepts (`kg`, `reps`, `mins_secs`; a time is
      in seconds and lower is better);
    * `anchors` – per division (`women`, `men`), four `{value, points}`
      pairs (20, 50, 75, 95). Points between anchors are interpolated
      linearly; below the first anchor they fall towards 0, above the last
      they rise slowly towards 100. Without a division the mean of the two is
      used, and the profile says so.

  The anchors are coarse population standards for adults who train in a
  box (roughly: 20 «started», 50 «trained», 75 «strong club athlete»,
  95 «competitive»). They are part of the algorithm version: changing a
  number is a new version (`FitnessProfile.algorithm/0`), never an edit.

  PR names match by `aliases` after `normalize/1` (lower case, accents and
  punctuation dropped), in English and Greek.
  """

  @domains ~w(strength power gymnastics monostructural metcon)

  # Research-based values (2026-11-03, /mnt/project-files/milos/
  # fitness-anchors-research-2026-11-03.md, copied to docs/research/):
  # Meier et al. 2021 (162 box members), Mangine et al. 2018 (CrossFit
  # benchmark deciles), Concept2 2025 rankings (ages 30–39), Strength Level,
  # CrossFit.com tiers, Riegel. ANR 2026-11-03: in use now; the reviewing
  # coach (xristoforos_rigas) confirms them and any objection becomes a new
  # algorithm version.
  #
  # {key, domain, unit, aliases, women anchors, men anchors}
  @catalog [
    {"back_squat", "strength", "kg", ["back squat", "squat", "πισω καθισμα", "καθισμα"],
     [45, 75, 100, 125], [75, 120, 155, 190]},
    {"front_squat", "strength", "kg", ["front squat", "μπροστινο καθισμα"], [38, 62, 82, 105],
     [60, 100, 130, 160]},
    {"deadlift", "strength", "kg", ["deadlift", "dead lift", "ασκηση θανατου", "νεκρη αρση"],
     [60, 95, 125, 150], [95, 150, 190, 230]},
    {"bench_press", "strength", "kg", ["bench press", "bench", "πιεσεις παγκου"],
     [30, 45, 60, 75], [60, 90, 115, 135]},
    {"strict_press", "strength", "kg",
     ["strict press", "shoulder press", "press", "overhead press", "military press"],
     [25, 35, 45, 55], [40, 60, 75, 90]},
    {"clean", "power", "kg",
     ["clean", "power clean", "squat clean", "clean and jerk", "clean & jerk", "clean jerk"],
     [35, 55, 75, 95], [55, 90, 115, 140]},
    {"snatch", "power", "kg", ["snatch", "power snatch", "squat snatch", "αρπαγη"],
     [25, 43, 58, 75], [40, 70, 90, 110]},
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
    {"toes_to_bar", "gymnastics", "reps", ["toes to bar", "t2b", "ttb"], [2, 10, 22, 35],
     [3, 12, 25, 40]},
    {"push_ups", "gymnastics", "reps", ["push ups", "push up", "pushups", "καμψεις"],
     [5, 20, 35, 50], [10, 30, 50, 70]},
    {"row_500m", "monostructural", "mins_secs", ["500m row", "row 500m", "500 m row", "κωπη 500"],
     [132, 117, 106, 98], [115, 100, 90, 84]},
    {"row_2k", "monostructural", "mins_secs",
     ["2k row", "2000m row", "row 2k", "row 2000m", "κωπη 2000"], [590, 525, 485, 455],
     [520, 465, 425, 395]},
    {"run_1_mile", "monostructural", "mins_secs", ["1 mile run", "mile run", "mile", "1 mile"],
     [660, 510, 440, 390], [570, 435, 380, 330]},
    {"run_5k", "monostructural", "mins_secs", ["5k run", "5k", "5km run", "5 km", "τρεξιμο 5km"],
     [2100, 1710, 1470, 1300], [1800, 1440, 1260, 1110]},
    {"fran", "metcon", "mins_secs", ["fran"], [630, 360, 255, 165], [540, 300, 210, 135]},
    {"grace", "metcon", "mins_secs", ["grace"], [450, 240, 165, 115], [390, 210, 135, 90]},
    {"helen", "metcon", "mins_secs", ["helen"], [960, 720, 600, 520], [840, 630, 540, 460]},
    {"diane", "metcon", "mins_secs", ["diane"], [1020, 660, 420, 260], [900, 540, 330, 200]},
    {"isabel", "metcon", "mins_secs", ["isabel"], [600, 390, 225, 135], [540, 330, 195, 115]},
    {"karen", "metcon", "mins_secs", ["karen"], [900, 630, 480, 375], [840, 570, 420, 330]},
    {"cindy", "metcon", "reps", ["cindy"], [8, 15, 20, 25], [10, 17, 22, 27]}
  ]

  @points [20, 50, 75, 95]

  # ADR-395 (algorithm v2, ANR mockup «Επίπεδο φυσικής κατάστασης v2» A):
  # the lifts read as a multiple of the person's body weight when they gave
  # it: the kg anchors above divided by 63 kg (women) and 82 kg (men),
  # rounded to 0.05, checked against Strength Level's bodyweight tables.
  #
  # {key, women ×body weight, men ×body weight}
  @ratio_catalog [
    {"back_squat", [0.70, 1.20, 1.60, 2.00], [0.90, 1.45, 1.90, 2.30]},
    {"front_squat", [0.60, 1.00, 1.30, 1.65], [0.75, 1.20, 1.60, 1.95]},
    {"deadlift", [0.95, 1.50, 2.00, 2.40], [1.15, 1.85, 2.30, 2.80]},
    {"bench_press", [0.50, 0.70, 0.95, 1.20], [0.75, 1.10, 1.40, 1.65]},
    {"strict_press", [0.40, 0.55, 0.70, 0.85], [0.50, 0.75, 0.90, 1.10]},
    {"clean", [0.55, 0.85, 1.20, 1.50], [0.65, 1.10, 1.40, 1.70]},
    {"snatch", [0.40, 0.70, 0.90, 1.20], [0.50, 0.85, 1.10, 1.35]}
  ]

  # ADR-395: how much easier every anchor gets per age band from 35, in
  # percent, per division (`women`, `men`): weights and reps × (1 − p/100),
  # times × (1 + p/100). From the CrossFit Open 2023–2024 leaderboards
  # (~5,000 athletes per sex per year, same peer percentile per band; strength
  # and conditioning declined alike up to 54), extended from 55 with the
  # Open's masters loads and published decline data (WMA age grading,
  # masters weightlifting). ANR 2026-11-03: in use until the coach objects.
  #
  # %{"35_39" => %{"women" => p, "men" => p}, ...}
  @age_factors %{
    "35_39" => %{"women" => 5, "men" => 5},
    "40_44" => %{"women" => 8, "men" => 10},
    "45_49" => %{"women" => 13, "men" => 15},
    "50_54" => %{"women" => 20, "men" => 20},
    "55_59" => %{"women" => 26, "men" => 25},
    "60_plus" => %{"women" => 33, "men" => 30}
  }

  @age_bands [{35, 39}, {40, 44}, {45, 49}, {50, 54}, {55, 59}, {60, nil}]

  def domains, do: @domains

  @doc "Whether the age bands have their percentages (asked for a birth year only then)."
  def age_ready?, do: map_size(@age_factors) > 0

  @doc "The age band of an age in years (`\"40_44\"`, `\"60_plus\"`), or nil under 35."
  def age_band(age) when is_integer(age) do
    Enum.find_value(@age_bands, fn
      {from, nil} when age >= from -> "#{from}_plus"
      {from, to} when age >= from and age <= to -> "#{from}_#{to}"
      _band -> nil
    end)
  end

  def age_band(_age), do: nil

  @doc "The percentage an age band eases the anchors by for a division (nil: none)."
  def age_factor(nil, _division), do: nil

  def age_factor(band, division) do
    case Map.get(@age_factors, band) do
      nil -> nil
      %{"women" => women, "men" => men} when is_nil(division) -> (women + men) / 2
      %{} = per_division -> Map.get(per_division, division)
    end
  end

  @doc """
  Every benchmark: `%{key, domain, unit, lower_is_better, anchors, ratio_anchors}`;
  `anchors` (and `ratio_anchors`, the lifts only, else nil) are keyed by
  `"women"`, `"men"` and `nil` (the neutral mean).
  """
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
    ratio =
      case List.keyfind(@ratio_catalog, key, 0) do
        {^key, ratio_women, ratio_men} -> anchors(ratio_women, ratio_men)
        nil -> nil
      end

    %{
      key: key,
      ratio_anchors: ratio,
      domain: domain,
      unit: unit,
      lower_is_better: unit == "mins_secs",
      aliases: Enum.map(aliases, &normalize/1),
      anchors: anchors(women, men)
    }
  end

  defp anchors(women, men) do
    %{
      "women" => Enum.zip(women, @points),
      "men" => Enum.zip(men, @points),
      nil => Enum.zip(Enum.zip_with(women, men, &((&1 + &2) / 2)), @points)
    }
  end
end
