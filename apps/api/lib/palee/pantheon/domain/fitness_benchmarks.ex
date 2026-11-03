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

  # ADR-395 (algorithm v2, ANR mockup «Επίπεδο φυσικής κατάστασης v2» A):
  # the lifts read as a multiple of the person's body weight when they gave
  # it. Proposals for the coach review (Claude Doc «Όρια … για έλεγχο από
  # coach»): the kg anchors above divided by 63 kg (women) and 82 kg (men),
  # rounded to 0.05. NEEDS COACH REVIEW like every anchor here.
  #
  # {key, women ×body weight, men ×body weight}
  @ratio_catalog [
    {"back_squat", [0.65, 1.05, 1.50, 2.00], [0.75, 1.20, 1.70, 2.20]},
    {"front_squat", [0.55, 0.85, 1.25, 1.65], [0.60, 1.05, 1.45, 1.90]},
    {"deadlift", [0.80, 1.35, 1.90, 2.55], [1.00, 1.60, 2.20, 2.80]},
    {"bench_press", [0.50, 0.70, 1.05, 1.35], [0.60, 1.00, 1.35, 1.70]},
    {"strict_press", [0.30, 0.55, 0.75, 1.00], [0.45, 0.65, 0.90, 1.15]},
    {"clean", [0.55, 0.85, 1.20, 1.50], [0.60, 1.00, 1.35, 1.70]},
    {"snatch", [0.40, 0.70, 0.95, 1.25], [0.50, 0.80, 1.10, 1.40]}
  ]

  # ADR-395: how much easier every anchor gets per age band from 35, in
  # percent, per division (`women`, `men`): weights and reps × (1 − p/100),
  # times × (1 + p/100). The reviewing coach sets these numbers (ANR
  # 2026-11-03); none is invented, so until they are in, age changes
  # nothing and the card does not ask for a birth year.
  #
  # %{"35_39" => %{"women" => p, "men" => p}, ...}
  @age_factors %{}

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
