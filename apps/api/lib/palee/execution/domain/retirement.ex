defmodule Palee.Execution.Domain.Retirement do
  @moduledoc """
  Παραίτηση (ADR-549): whether an athlete gave up a section whose clock is set
  by time, pure.

  In a time-set section (AMRAP, EDT, EMOM and Tabata-like windows, fixed
  intervals, a plan AMRAP/EMOM/Intervals with a set number of windows) the
  score is the work done (rounds, reps, kcal, metres, …), so finishing early
  is never "being fast": the only ways to give up are to stop the clock
  before it ran out, or to let it run without working. Count-ups (For Time,
  ladders, kcal targets) and open-ended windows (Death By, EMOM to failure)
  are not time-set: stopping is how they end.

  Facts per time-set section, from what the server already validates:

    * `planned_ms` — the authored length (countdowns plus a fixed number of
      windows, rests inside the section included);
    * `adjusted_ms` — the length after the athlete's own "+/−30 s"
      (`DurationAdjustments`);
    * `ran_ms` — the section's active time (`section_elapsed_ms`);
    * work taps — the active section times (ms) of the athlete's work taps
      (a round, a checked exercise, a finished plan step), recorded by the
      device in `kpi_counters["activity"]` (see `merge_activity/3`).

  Verdicts, most certain first:

    * `stopped_early` — ran less than the adjusted length (beyond the clock
      tolerance): the clock was stopped or the section was never reached;
    * `shortened` — ran the full adjusted length, but the athlete took time
      off the authored clock;
    * `idle` — ran the full length, but after the last work tap the clock
      ran on for more than `idle_factor` × the athlete's own median time
      between taps in that section (needs at least #{2} taps for a pace);
    * `full` — ran the full length and kept tapping;
    * `unknown` — ran the full length with too few taps to tell (an athlete
      who only types the score at the end).

  An athlete's answer (`state.answers`, section id => `gave_up` |
  `chose_shorter`) applies to a `stopped_early` section only: `chose_shorter`
  makes it `shortened`, `gave_up` confirms it; both are kept as `answer`.

  `idle_factor` comes from the caller (`config :palee, :retirement_idle_factor`);
  nil records the facts without the `idle` verdict.
  """

  # Clocks commit whole milliseconds and the device may round the last tick.
  @clock_tolerance_ms 1_000
  @min_taps_for_pace 2
  @max_taps_per_section 300
  @max_sections 60
  @max_ms 86_400_000

  def clock_tolerance_ms, do: @clock_tolerance_ms
  def max_taps_per_section, do: @max_taps_per_section

  @doc """
  The time-set sections of a timer sequence: `%{section_id => %{planned_ms,
  format, scored}}`. A section qualifies when every work segment of it has a
  fixed length and it is not scored by time.
  """
  def time_set_sections(segments) when is_list(segments) do
    segments
    |> Enum.reject(&(value(&1, :between_sections) == true))
    |> Enum.group_by(&to_string(value(&1, :section_id)))
    |> Enum.flat_map(fn {section_id, section_segments} ->
      lengths = Enum.map(section_segments, &fixed_ms/1)
      work = Enum.filter(section_segments, &(to_string(value(&1, :phase)) == "work"))

      if work != [] and Enum.all?(lengths, &is_integer/1) and Enum.sum(lengths) > 0 and
           not scored_by_time?(section_segments) do
        first = hd(section_segments)

        [
          {section_id,
           %{
             planned_ms: Enum.sum(lengths),
             format: to_string(value(first, :format)),
             section_name: value(first, :section_name),
             scored: Enum.any?(section_segments, &(value(&1, :scoreable) == true))
           }}
        ]
      else
        []
      end
    end)
    |> Map.new()
  end

  def time_set_sections(_segments), do: %{}

  @doc "Whether a segment list has any time-set section."
  def time_set?(segments), do: time_set_sections(segments) != %{}

  @doc """
  Merges the device's work taps into the stored counters, keeping only
  time-set sections of `segments` and valid times. Taps only accumulate: a
  stale or replayed snapshot never removes one.
  """
  def merge_activity(counters, incoming, segments) when is_list(segments) do
    counters = counters || %{}
    sections = time_set_sections(segments)
    existing = stringify_keys(counters["activity"] || %{})
    incoming = if is_map(incoming), do: stringify_keys(incoming), else: %{}

    merged =
      (Map.keys(existing) ++ Map.keys(incoming))
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(sections, &1))
      |> Enum.take(@max_sections)
      |> Map.new(fn id ->
        taps =
          (taps(existing[id]) ++ taps(incoming[id]))
          |> Enum.uniq()
          |> Enum.sort()
          |> Enum.take(@max_taps_per_section)

        {id, taps}
      end)
      |> Map.reject(fn {_id, taps} -> taps == [] end)

    if merged == %{},
      do: Map.delete(counters, "activity"),
      else: Map.put(counters, "activity", merged)
  end

  def merge_activity(counters, _incoming, _segments), do: counters || %{}

  @doc """
  The retirement facts of a finished execution: `%{"verdict", "sections"}`,
  or nil when the workout has no time-set section. `verdict` is the most
  certain section verdict (`stopped_early` > `shortened` > `idle` > `unknown`
  > `full`).
  """
  def assess(segments, state, idle_factor) when is_list(segments) do
    case time_set_sections(segments) do
      empty when empty == %{} ->
        nil

      sections ->
        elapsed = stringify_keys(value(state, :section_elapsed_ms) || %{})
        activity = stringify_keys(value(state, :activity) || %{})
        shortened = shortened_ms_by_section(value(state, :duration_adjustments) || %{})
        answers = stringify_keys(value(state, :answers) || %{})

        rows =
          sections
          |> Enum.map(fn {id, section} ->
            section_facts(id, section, %{
              ran_ms: non_negative(elapsed[id]),
              taps: taps(activity[id]),
              shortened_ms: Map.get(shortened, id, 0),
              idle_factor: idle_factor
            })
            |> apply_answer(answers[id])
          end)
          |> Enum.sort_by(& &1["section_id"])

        %{"verdict" => overall(rows), "sections" => rows}
    end
  end

  def assess(_segments, _state, _idle_factor), do: nil

  @doc """
  ADR-549 (2B): when a result ran only part of a time-set section's clock
  (`stopped_early` or `shortened`), `%{ran_ms, planned_ms}` of that section,
  the one with `section_id` first; nil when every time-set section ran in
  full or the facts are missing. A neutral fact for the athlete's own result
  and the leaderboard's time mark, never a verdict shown to others.
  """
  def part_of_time(counters, section_id \\ nil)

  def part_of_time(%{} = counters, section_id) do
    sections =
      case counters["retirement"] || counters[:retirement] do
        %{"sections" => list} when is_list(list) -> Enum.filter(list, &is_map/1)
        _none -> []
      end

    short = Enum.filter(sections, &(&1["verdict"] in ~w(stopped_early shortened)))

    case Enum.find(short, &(&1["section_id"] == to_string(section_id))) || List.first(short) do
      %{"ran_ms" => ran, "planned_ms" => planned} when is_integer(ran) and is_integer(planned) ->
        %{ran_ms: ran, planned_ms: planned}

      _full ->
        nil
    end
  end

  def part_of_time(_counters, _section_id), do: nil

  @verdict_rank %{
    "stopped_early" => 0,
    "shortened" => 1,
    "idle" => 2,
    "unknown" => 3,
    "full" => 4
  }

  @doc "Every verdict, most certain first."
  def verdicts, do: @verdict_rank |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))

  @doc "Whether a verdict means the athlete gave up (certain or probable)."
  def retired?(verdict), do: verdict in ~w(stopped_early idle)

  defp overall(rows), do: rows |> Enum.map(& &1["verdict"]) |> Enum.min_by(&@verdict_rank[&1])

  defp section_facts(id, section, facts) do
    adjusted = max(section.planned_ms - facts.shortened_ms, 0)
    gaps = gaps(facts.taps)
    median_gap = median(gaps)
    last_tap = List.last(facts.taps)
    idle_tail = if last_tap, do: max(facts.ran_ms - last_tap, 0), else: nil

    verdict =
      cond do
        facts.ran_ms < adjusted - @clock_tolerance_ms -> "stopped_early"
        facts.shortened_ms > @clock_tolerance_ms -> "shortened"
        length(facts.taps) < @min_taps_for_pace -> "unknown"
        idle?(idle_tail, median_gap, facts.idle_factor) -> "idle"
        true -> "full"
      end

    %{
      "section_id" => id,
      "section_name" => section.section_name,
      "format" => section.format,
      "scored" => section.scored,
      "planned_ms" => section.planned_ms,
      "adjusted_ms" => adjusted,
      "ran_ms" => facts.ran_ms,
      "stopped_early_ms" => max(adjusted - facts.ran_ms, 0),
      "taps" => length(facts.taps),
      "last_tap_ms" => last_tap,
      "median_tap_gap_ms" => median_gap,
      "longest_tap_gap_ms" => if(gaps == [], do: nil, else: Enum.max(gaps)),
      "idle_tail_ms" => idle_tail,
      "verdict" => verdict
    }
  end

  # The athlete's own answer to «Σταμάτησες πριν τελειώσει ο χρόνος;», only
  # for a section that was stopped early: wanting a shorter WOD makes it a
  # shortened clock, not a retirement; giving up confirms it.
  defp apply_answer(%{"verdict" => "stopped_early"} = row, "chose_shorter"),
    do: Map.merge(row, %{"verdict" => "shortened", "answer" => "chose_shorter"})

  defp apply_answer(%{"verdict" => "stopped_early"} = row, "gave_up"),
    do: Map.put(row, "answer", "gave_up")

  defp apply_answer(row, _answer), do: row

  defp idle?(tail, median, factor)
       when is_integer(tail) and is_integer(median) and median > 0 and is_number(factor) and
              factor > 0,
       do: tail > factor * median

  defp idle?(_tail, _median, _factor), do: false

  # Time to the first tap, then between taps.
  defp gaps([]), do: []

  defp gaps([first | _rest] = taps),
    do: [first | taps |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)]

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1,
      do: Enum.at(sorted, middle),
      else: div(Enum.at(sorted, middle - 1) + Enum.at(sorted, middle), 2)
  end

  # Seconds the athlete took off a section's clocks ("−30 s"), in ms.
  defp shortened_ms_by_section(adjustments) when is_map(adjustments) do
    adjustments
    |> Map.values()
    |> Enum.filter(&is_map/1)
    |> Enum.group_by(&to_string(value(&1, :section_id)), &(value(&1, :delta_seconds) || 0))
    |> Map.new(fn {id, deltas} -> {id, max(-Enum.sum(deltas), 0) * 1_000} end)
  end

  defp shortened_ms_by_section(_adjustments), do: %{}

  defp fixed_ms(segment) do
    seconds = value(segment, :duration_seconds)

    case to_string(value(segment, :kind)) do
      "countdown" when is_integer(seconds) and seconds > 0 ->
        seconds * 1_000

      "interval_cycle" ->
        windows = value(segment, :total_rounds)
        pattern = pattern(segment, seconds)

        if is_integer(windows) and windows > 0 and pattern != [] do
          pattern |> Stream.cycle() |> Enum.take(windows) |> Enum.sum() |> Kernel.*(1_000)
        end

      _open ->
        nil
    end
  end

  defp pattern(segment, seconds) do
    config = value(segment, :timer_config) || %{}

    case value(config, :interval_pattern_seconds) do
      [_ | _] = pattern ->
        if Enum.all?(pattern, &(is_integer(&1) and &1 > 0)), do: pattern, else: []

      _none ->
        if is_integer(seconds) and seconds > 0, do: [seconds], else: []
    end
  end

  defp scored_by_time?(segments) do
    Enum.any?(segments, fn segment ->
      config = value(segment, :score_config) || %{}
      metrics = value(config, :metrics)

      to_string(value(config, :type)) == "time" or
        (is_list(metrics) and metrics != [] and
           Enum.all?(metrics, &(is_map(&1) and to_string(value(&1, :kind)) == "time")))
    end)
  end

  defp taps(list) when is_list(list),
    do: Enum.filter(list, &(is_integer(&1) and &1 >= 0 and &1 <= @max_ms))

  defp taps(_other), do: []

  defp non_negative(ms) when is_integer(ms) and ms >= 0, do: ms
  defp non_negative(_ms), do: 0

  defp stringify_keys(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
  defp stringify_keys(_other), do: %{}

  defp value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp value(_map, _key), do: nil
end
