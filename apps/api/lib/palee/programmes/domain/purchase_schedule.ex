defmodule Palee.Programmes.Domain.PurchaseSchedule do
  @moduledoc """
  ADR-540: a bought programme as a sequence of days, pure.

  Day `n` of the version falls on `starts_on + n` (ADR-371) unless the buyer
  moved it: `day_dates` keeps the days whose date changed (`"n" =>
  "YYYY-MM-DD"`), `skipped_days` the days the buyer let go. A training day
  (one with WODs) is, in this order:

    * `done`: every WOD of the day was finished (an in-app run or a
      training-log entry of its assigned workout);
    * `skipped`: the buyer chose «Παράλειψη»;
    * `behind` («Έμεινε πίσω»): its date is before today;
    * `today`, `upcoming`: by its date.

  A day without WODs is `rest`; it moves with the training day before it.

  «Κάν' τη σήμερα» (`do_today/4`) on a behind day moves it to today and the
  days after it that are neither done nor skipped by the same number of
  days, so the order and the gaps stay as the coach wrote them; done and
  skipped days keep their dates. The purchase's `ends_on` follows the last
  day. «Παράλειψη» (`skip/3`) marks a behind day skipped and moves
  nothing.

  The cap: a programme never ends more than its own length after its
  planned end (`latest_end/2`: `planned_ends_on + weeks × 7`), so a
  6-week programme takes at most 12 weeks. A move past it is refused
  (`:programme_schedule_limit`); skipping is always possible.
  """

  @statuses ~w(done skipped behind today upcoming rest)

  def statuses, do: @statuses

  @doc """
  Every day of the programme (`0..weeks*7-1`) with its date and status.

  `version`: `%{weeks, days: [%{"day", "workout_id", ...}]}`; `purchase`:
  `starts_on`, `day_dates`, `skipped_days`; `done`: the training days whose
  WODs are all finished.
  """
  def days(version, purchase, done, %Date{} = today) do
    by_day = Enum.group_by(version.days, & &1["day"])
    skipped = MapSet.new(purchase.skipped_days || [])
    done = MapSet.new(done)

    {rows, _delta} =
      Enum.map_reduce(0..(version.weeks * 7 - 1), 0, fn day, delta ->
        original = Date.add(purchase.starts_on, day)

        case Map.get(by_day, day) do
          nil ->
            {row(day, Date.add(original, delta), "rest", []), delta}

          workouts ->
            date = date_of(purchase, day)

            status =
              cond do
                MapSet.member?(done, day) -> "done"
                MapSet.member?(skipped, day) -> "skipped"
                true -> by_date(date, today)
              end

            {row(day, date, status, workouts), Date.diff(date, original)}
        end
      end)

    rows
  end

  defp row(day, date, status, workouts) do
    %{
      day: day,
      week: div(day, 7) + 1,
      weekday: rem(day, 7),
      date: date,
      status: status,
      workouts: workouts
    }
  end

  defp by_date(date, today) do
    case Date.compare(date, today) do
      :lt -> "behind"
      :eq -> "today"
      :gt -> "upcoming"
    end
  end

  @doc "The date of training day `day`: the buyer's move, else `starts_on + day`."
  def date_of(purchase, day) do
    case Map.get(purchase.day_dates || %{}, Integer.to_string(day)) do
      nil -> Date.add(purchase.starts_on, day)
      %Date{} = date -> date
      iso -> Date.from_iso8601!(iso)
    end
  end

  @doc "Counts for the progress bar («6 / 24»): training days only."
  def progress(days) do
    training = Enum.reject(days, &(&1.status == "rest"))
    counts = Enum.frequencies_by(training, & &1.status)
    count = &Map.get(counts, &1, 0)

    %{
      total: length(training),
      done: count.("done"),
      skipped: count.("skipped"),
      behind: count.("behind"),
      remaining: length(training) - count.("done") - count.("skipped")
    }
  end

  @doc "The earliest behind day (the one the «Έμεινε πίσω» card names), or nil."
  def next_behind(days), do: Enum.find(days, &(&1.status == "behind"))

  @doc "The latest date the programme may end on (the cap)."
  def latest_end(purchase, weeks), do: Date.add(planned_end(purchase), weeks * 7)

  defp planned_end(purchase), do: Map.get(purchase, :planned_ends_on) || purchase.ends_on

  @doc """
  «Κάν' τη σήμερα»: `{:ok, %{day_dates, ends_on, moves}}` with `moves`
  `[%{day, from, to}]`, or `{:error, reason}`
  (`:programme_day_not_found`, `:programme_day_not_behind`,
  `:programme_schedule_limit`).
  """
  def do_today(days, purchase, day, %Date{} = today) do
    weeks = div(length(days), 7)

    with {:ok, target} <- find(days, day),
         true <- target.status == "behind" || {:error, :programme_day_not_behind} do
      delta = Date.diff(today, target.date)

      moves =
        for row <- days,
            row.day >= day,
            row.status not in ["rest", "done", "skipped"] do
          %{day: row.day, from: row.date, to: Date.add(row.date, delta)}
        end

      day_dates =
        Enum.reduce(moves, purchase.day_dates || %{}, fn move, acc ->
          if Date.compare(move.to, Date.add(purchase.starts_on, move.day)) == :eq,
            do: Map.delete(acc, Integer.to_string(move.day)),
            else: Map.put(acc, Integer.to_string(move.day), Date.to_iso8601(move.to))
        end)

      moved = %{purchase | day_dates: day_dates}
      ends_on = end_date(days, moved, weeks)

      if Date.compare(ends_on, latest_end(purchase, weeks)) == :gt,
        do: {:error, :programme_schedule_limit},
        else: {:ok, %{day_dates: day_dates, ends_on: ends_on, moves: moves}}
    end
  end

  # The last day of the programme after the moves: its own date (a rest
  # day moves with the training day before it), never before the planned end.
  defp end_date(days, purchase, weeks) do
    shifted = days(%{weeks: weeks, days: training_rows(days)}, purchase, [], purchase.starts_on)
    last = List.last(shifted).date

    [planned_end(purchase), last | Enum.map(shifted, & &1.date)]
    |> Enum.max(Date)
  end

  defp training_rows(days) do
    for row <- days, row.status != "rest", workout <- row.workouts, do: workout
  end

  @doc """
  Whether «Κάν' τη σήμερα» is possible for a behind day (within the cap).
  """
  def can_do_today?(days, purchase, day, today),
    do: match?({:ok, _}, do_today(days, purchase, day, today))

  @doc """
  «Παράλειψη»: `{:ok, skipped_days}` or `{:error, reason}`. Only a behind
  day is skipped (its WODs stay in the past, nothing moves); skipping it
  again is a no-op.
  """
  def skip(days, purchase, day) do
    with {:ok, target} <- find(days, day) do
      case target.status do
        "skipped" -> {:ok, purchase.skipped_days || []}
        "behind" -> {:ok, Enum.sort([day | purchase.skipped_days || []])}
        _other -> {:error, :programme_day_not_behind}
      end
    end
  end

  defp find(days, day) do
    case Enum.find(days, &(&1.day == day)) do
      nil -> {:error, :programme_day_not_found}
      %{status: "rest"} -> {:error, :programme_day_not_found}
      row -> {:ok, row}
    end
  end
end
