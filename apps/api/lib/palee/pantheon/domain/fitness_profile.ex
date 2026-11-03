defmodule Palee.Pantheon.Domain.FitnessProfile do
  @moduledoc """
  ADR-358 (CP-D6): an explainable fitness score per domain and «τι να
  δουλέψεις», from the person's own PRs and training. Algorithm
  `fitness-profile` version 1.

  1. **Benchmarks.** Each PR whose name is a known benchmark
     (`FitnessBenchmarks.match/1`) and whose unit fits is read: a weight PR
     as its estimated one-rep max (Epley, as `StrengthTrend`), reps and
     times as recorded. Its points (0–100) are interpolated between the
     benchmark's anchors for the person's division.
  2. **Domains.** A domain's score is the mean of its benchmarks' points,
     a PR older than `@stale_days` counting half. `confidence` is `low`
     with one benchmark, `medium` with two, `high` with three or more.
  3. **Overall.** The mean of the scored domains, given only when at least
     `@min_domains` domains have a score: two lifts are not a fitness level.
  4. **What to work on** (`focus`, at most three, most useful first):
     * `weakest_domain` – a scored domain at least `@gap` points below the
       mean of the others;
     * `untested_domain` – a domain without a benchmark (log one to see it);
     * `undertrained_quality` – a domain whose training quality got under
       `@low_share` of the most trained one in the last 12 weeks, when at
       least 4 sessions were logged;
     * `stale_benchmark` – a domain scored only from PRs older than
       `@stale_days` (test it again).
     A domain touched by an active injury is never suggested, and with an
     active injury of unknown domains nothing is; the profile carries
     `injury_caution` instead.

  Every number comes with what produced it (`reasons`), so the screen can
  show the reasoning. Comparison is with the person's own results and fixed
  standards only, never with other people (principle §4.4).
  """

  alias Palee.Pantheon.Domain.{FitnessBenchmarks, StrengthTrend}

  @algorithm %{id: "fitness-profile", version: 1}
  @stale_days 365
  @min_domains 2
  @gap 15
  @low_share 0.25
  @min_sessions 4
  @max_focus 3

  # The training quality (ADR-165) each domain mostly trains.
  @domain_quality %{
    "strength" => "strength",
    "power" => "power",
    "gymnastics" => "coordination",
    "monostructural" => "cardiorespiratory-endurance",
    "metcon" => "stamina"
  }

  def algorithm, do: @algorithm

  @type input :: %{
          required(:prs) => [map()],
          required(:today) => Date.t(),
          optional(:division) => String.t() | nil,
          optional(:qualities) => %{sessions: non_neg_integer(), qualities: [map()]} | nil,
          optional(:injured_domains) => [String.t()],
          optional(:active_injury) => boolean()
        }

  @doc "The profile: overall, domains with their reasons, focus and the algorithm."
  @spec build(input()) :: map()
  def build(%{prs: prs, today: %Date{} = today} = input) do
    division = Map.get(input, :division)
    injured = MapSet.new(Map.get(input, :injured_domains, []))

    readings =
      prs
      |> Enum.map(&reading(&1, division, today))
      |> Enum.reject(&is_nil/1)
      |> best_per_benchmark()

    domains =
      Enum.map(FitnessBenchmarks.domains(), fn domain ->
        domain_score(domain, Enum.filter(readings, &(&1.domain == domain)))
      end)

    scored = Enum.filter(domains, & &1.score)

    %{
      algorithm: @algorithm,
      division: division,
      neutral_standards: is_nil(division),
      overall: overall(scored),
      domains: domains,
      focus: focus(domains, Map.get(input, :qualities), injured, Map.get(input, :active_injury, false)),
      injury_caution: Map.get(input, :active_injury, false) or MapSet.size(injured) > 0,
      benchmarks_known: length(FitnessBenchmarks.all())
    }
  end

  @doc "Points of a value on a benchmark's anchors (0..100, one decimal)."
  def points(value, anchors, lower_is_better) do
    # Times: a lower value is better, so flip both sides of the scale.
    {value, anchors} =
      if lower_is_better,
        do: {-value, Enum.map(anchors, fn {v, p} -> {-v, p} end)},
        else: {value, anchors}

    [{v0, _p0} | _rest] = anchors
    {vn, pn} = List.last(anchors)

    raw =
      cond do
        value <= v0 -> below_first(value, anchors)
        value >= vn -> min(100.0, pn + (value - vn) / max(abs(vn), 1) * 50)
        true -> between(value, anchors)
      end

    (raw * 1.0) |> max(0.0) |> min(100.0) |> Float.round(1)
  end

  # Below the first anchor: points fall linearly to 0 at the value as far
  # below the first anchor as the second is above it.
  defp below_first(value, [{v0, p0}, {v1, _p1} | _rest]) do
    span = max(v1 - v0, 1.0e-9)
    p0 * (1 - (v0 - value) / span)
  end

  defp between(value, anchors) do
    anchors
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [{a, pa}, {b, pb}] ->
      if value >= a and value <= b, do: pa + (value - a) / max(b - a, 1.0e-9) * (pb - pa)
    end)
  end

  defp reading(pr, division, today) do
    with %{} = benchmark <- FitnessBenchmarks.match(field(pr, :name)),
         true <- field(pr, :unit) == benchmark.unit,
         value when is_number(value) <- value(pr, benchmark),
         %Date{} = on <- date(field(pr, :beaten_on)) do
      anchors = Map.fetch!(benchmark.anchors, division)
      age = Date.diff(today, on)

      %{
        benchmark: benchmark.key,
        domain: benchmark.domain,
        name: field(pr, :name),
        value: value,
        unit: benchmark.unit,
        estimated: benchmark.unit == "kg" and reps(pr) > 1,
        points: points(value, anchors, benchmark.lower_is_better),
        anchors: Enum.map(anchors, fn {v, p} -> %{value: v, points: p} end),
        beaten_on: on,
        age_days: age,
        stale: age > @stale_days
      }
    else
      _not_a_benchmark -> nil
    end
  end

  defp value(pr, %{unit: "kg"}) do
    case number(field(pr, :current_score)) do
      nil -> nil
      load -> StrengthTrend.estimated_one_rep_max(load, reps(pr))
    end
  end

  defp value(pr, _benchmark), do: number(field(pr, :current_score))

  # Two PRs for one benchmark (e.g. «Clean» and «Power clean»): the best counts.
  defp best_per_benchmark(readings) do
    readings
    |> Enum.group_by(& &1.benchmark)
    |> Enum.map(fn {_key, list} -> Enum.max_by(list, & &1.points) end)
    |> Enum.sort_by(&{&1.domain, -&1.points})
  end

  defp domain_score(domain, []),
    do: %{domain: domain, score: nil, confidence: nil, stale: false, reasons: []}

  defp domain_score(domain, readings) do
    weighted = Enum.map(readings, &{&1.points, if(&1.stale, do: 0.5, else: 1.0)})
    total_weight = weighted |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    score = Enum.sum(Enum.map(weighted, fn {p, w} -> p * w end)) / total_weight

    %{
      domain: domain,
      score: round(score),
      confidence: confidence(length(readings)),
      stale: Enum.all?(readings, & &1.stale),
      reasons: readings
    }
  end

  defp confidence(1), do: "low"
  defp confidence(2), do: "medium"
  defp confidence(_n), do: "high"

  defp overall(scored) when length(scored) < @min_domains, do: nil

  defp overall(scored) do
    %{
      score: round(Enum.sum(Enum.map(scored, & &1.score)) / length(scored)),
      domains_scored: length(scored),
      reason: "mean_of_domains"
    }
  end

  # An active injury whose domains are unknown (injuries name body parts, not
  # domains) could touch any domain, so nothing is suggested until it heals.
  defp focus(domains, qualities, injured, active_injury) do
    if active_injury and MapSet.size(injured) == 0,
      do: [],
      else: focus(domains, qualities, injured)
  end

  defp focus(domains, qualities, injured) do
    candidates =
      weakest(domains) ++ undertrained(domains, qualities) ++ stale(domains) ++ untested(domains)

    candidates
    |> Enum.reject(&MapSet.member?(injured, &1.domain))
    |> Enum.uniq_by(& &1.domain)
    |> Enum.take(@max_focus)
  end

  defp weakest(domains) do
    scored = Enum.filter(domains, & &1.score)

    scored
    |> Enum.map(fn domain ->
      others = Enum.reject(scored, &(&1.domain == domain.domain))

      case others do
        [] ->
          nil

        _others ->
          mean = Enum.sum(Enum.map(others, & &1.score)) / length(others)
          gap = round(mean - domain.score)

          if gap >= @gap,
            do: %{
              domain: domain.domain,
              kind: "weakest_domain",
              score: domain.score,
              others_mean: round(mean),
              gap: gap
            }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&(-&1.gap))
  end

  defp undertrained(_domains, nil), do: []
  defp undertrained(_domains, %{sessions: sessions}) when sessions < @min_sessions, do: []

  defp undertrained(domains, %{qualities: qualities}) do
    by_id = Map.new(qualities, &{&1.id, &1})

    domains
    |> Enum.map(fn domain ->
      quality = Map.get(@domain_quality, domain.domain)

      case Map.get(by_id, quality) do
        %{score: share} when is_number(share) and share < @low_share ->
          %{
            domain: domain.domain,
            kind: "undertrained_quality",
            quality: quality,
            share: Float.round(share * 1.0, 2)
          }

        _enough ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp stale(domains) do
    for %{stale: true, score: score} = domain when not is_nil(score) <- domains,
        do: %{domain: domain.domain, kind: "stale_benchmark"}
  end

  defp untested(domains) do
    for %{score: nil} = domain <- domains,
        do: %{
          domain: domain.domain,
          kind: "untested_domain",
          suggestions:
            FitnessBenchmarks.all()
            |> Enum.filter(&(&1.domain == domain.domain))
            |> Enum.map(& &1.key)
            |> Enum.take(3)
        }
  end

  defp reps(pr) do
    case field(pr, :supporting_metrics) do
      %{} = metrics ->
        case number(Map.get(metrics, "reps") || Map.get(metrics, :reps)) do
          reps when is_number(reps) and reps >= 1 -> reps
          _none -> 1
        end

      _none ->
        1
    end
  end

  defp number(%Decimal{} = value), do: Decimal.to_float(value)
  defp number(value) when is_number(value), do: value * 1.0

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp number(_value), do: nil

  defp date(%Date{} = date), do: date

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _invalid -> nil
    end
  end

  defp date(_value), do: nil

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
