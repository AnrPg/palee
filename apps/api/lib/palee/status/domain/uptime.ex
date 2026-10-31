defmodule Palee.Status.Domain.Uptime do
  @moduledoc """
  Uptime history from the daily probe counts (ADR-364).

  A probe that finds a component `degraded` counts as up (it works, slowly);
  only `down` counts against uptime. A day is `operational` with no
  degraded or down probe, `down` when at least 5% of its probes found the
  component down, `degraded` otherwise, and `no_data` when nothing was
  probed (before the page existed, or while the probe job was not running).

  Percentages are floats rounded to three decimals (99.982). Pure: callers
  pass the last day of the window.
  """

  alias Palee.Status.Domain.Components

  @max_days 90
  @down_share 0.05

  def max_days, do: @max_days

  @doc "Clamps a requested window to 1..90 days (default 90)."
  def window_days(nil), do: @max_days

  def window_days(days) when is_binary(days) do
    case Integer.parse(days) do
      {value, ""} -> window_days(value)
      _other -> @max_days
    end
  end

  def window_days(days) when is_integer(days), do: days |> max(1) |> min(@max_days)
  def window_days(_days), do: @max_days

  @doc "The first day of a window of `days` days ending on `last_day`."
  def first_day(%Date{} = last_day, days), do: Date.add(last_day, -(days - 1))

  @doc """
  One entry per component, in display order:
  `%{key, uptime_percent, days: [%{date, status, uptime_percent}]}`, oldest
  day first. `uptime_percent` is `nil` when nothing was probed.
  """
  def history(samples, %Date{} = last_day, days) do
    first = first_day(last_day, days)
    dates = Enum.map(0..(days - 1), &Date.add(first, &1))
    by_key = Enum.group_by(samples, & &1.component)

    Enum.map(Components.all(), fn key ->
      per_day = Map.new(Map.get(by_key, key, []), &{&1.day, &1})
      entries = Enum.map(dates, &day(&1, Map.get(per_day, &1)))
      in_window = Enum.flat_map(dates, &List.wrap(Map.get(per_day, &1)))

      %{key: key, uptime_percent: percent(in_window), days: entries}
    end)
  end

  @doc "The day's status from its counts."
  def day_status(nil), do: "no_data"
  def day_status(%{total: 0}), do: "no_data"

  def day_status(%{total: total, degraded: degraded, down: down}) do
    cond do
      down > 0 and down / total >= @down_share -> "down"
      down > 0 or degraded > 0 -> "degraded"
      true -> "operational"
    end
  end

  defp day(date, sample),
    do: %{date: date, status: day_status(sample), uptime_percent: percent(List.wrap(sample))}

  defp percent(samples) do
    total = samples |> Enum.map(& &1.total) |> Enum.sum()
    down = samples |> Enum.map(& &1.down) |> Enum.sum()

    if total == 0, do: nil, else: Float.round((total - down) * 100 / total, 3)
  end
end
