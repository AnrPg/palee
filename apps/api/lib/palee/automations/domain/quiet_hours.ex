defmodule Palee.Automations.Domain.QuietHours do
  @moduledoc """
  ADR-346: automatic messages never arrive at night. Quiet hours are a
  window of the box's own clock (default 21:00 to 09:00, `from` after
  `until` meaning it spans midnight); a message due inside it waits until
  the window ends. Pure; times are stored in UTC and read in the box's
  time zone (ADR-176/179), so daylight-saving changes are handled by the
  zone database.
  """

  alias Palee.TimeZones.ZonedTime

  @doc """
  The first moment at or after `at` (UTC) outside the quiet window in
  `time_zone`. `from` and `until` are `"HH:MM"`; equal ones mean no quiet
  hours.
  """
  @spec next_allowed(DateTime.t(), String.t(), String.t(), String.t()) :: DateTime.t()
  def next_allowed(%DateTime{} = at, time_zone, from, until) do
    zone = ZonedTime.or_default(time_zone)
    from = minutes(from)
    until = minutes(until)
    local = DateTime.shift_zone!(at, zone)
    now_minutes = local.hour * 60 + local.minute

    if quiet?(now_minutes, from, until) do
      end_date =
        if from > until and now_minutes >= from,
          do: Date.add(DateTime.to_date(local), 1),
          else: DateTime.to_date(local)

      end_date
      |> local_moment(until, zone)
      |> DateTime.shift_zone!("Etc/UTC")
    else
      at
    end
  end

  @doc "Whether a moment `minutes` after local midnight falls inside the window."
  def quiet?(_minutes, same, same), do: false
  def quiet?(minutes, from, until) when from < until, do: minutes >= from and minutes < until
  def quiet?(minutes, from, until), do: minutes >= from or minutes < until

  @doc """
  The UTC moment of `hour`:00 on the box's `date`, for the daily recipes.
  """
  def at_local_hour(%Date{} = date, hour, time_zone) do
    date
    |> local_moment(hour * 60, ZonedTime.or_default(time_zone))
    |> DateTime.shift_zone!("Etc/UTC")
  end

  # A local wall time that does not exist (the spring-forward gap) moves to
  # the first one after it; an ambiguous one takes the earlier.
  defp local_moment(date, minutes, zone) do
    time = Time.new!(div(minutes, 60), rem(minutes, 60), 0)

    case DateTime.new(date, time, zone) do
      {:ok, moment} -> moment
      {:ambiguous, first, _second} -> first
      {:gap, _before, after_gap} -> after_gap
      {:error, _reason} -> DateTime.new!(date, time, "Etc/UTC")
    end
  end

  defp minutes(<<h::binary-size(2), ":", m::binary-size(2)>>),
    do: String.to_integer(h) * 60 + String.to_integer(m)

  defp minutes(_other), do: 0
end
