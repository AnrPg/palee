defmodule Palee.Programmes.Domain.ProgrammeSchedule do
  @moduledoc """
  The dates a bought programme puts WODs on (ADR-371), pure: day `n` of a
  version falls on `starts_on + n`, in the seller's own calendar (a date,
  no time: ADR-176/179).
  """

  @doc """
  `[{date, day, workout_id}]` for the version's days on or after `from`
  (a purchase made after its start never back-fills past days).
  """
  def dates(days, %Date{} = starts_on, %Date{} = from) do
    days
    |> Enum.map(fn row -> {Date.add(starts_on, row["day"]), row["day"], row["workout_id"]} end)
    |> Enum.filter(fn {date, _day, _workout} -> Date.compare(date, from) != :lt end)
    |> Enum.sort_by(fn {date, day, workout} -> {Date.to_gregorian_days(date), day, workout} end)
  end

  @doc "Week number (1-based) and weekday index (0-based) of a programme day."
  def position(day) when is_integer(day) and day >= 0,
    do: %{week: div(day, 7) + 1, weekday: rem(day, 7)}
end
