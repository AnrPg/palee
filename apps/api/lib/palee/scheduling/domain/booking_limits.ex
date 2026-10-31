defmodule Palee.Scheduling.Domain.BookingLimits do
  @moduledoc """
  CP-A8 (ADR-342): how many classes a package lets a member book, pure.

    * `daily` – bookings on one gym-local day (the class's day);
    * `weekly` – bookings in one gym-local week, Monday to Sunday;
    * `open` – upcoming bookings held at once (classes after `now`).

  A limit of nil is no limit. `booked` are the start times of the member's
  live bookings (pending or approved, not a guest's, not waitlisted); the
  booking being made is not among them.
  """

  alias Palee.TimeZones.ZonedTime

  @type limits :: %{
          optional(:daily_booking_limit) => pos_integer() | nil,
          optional(:weekly_booking_limit) => pos_integer() | nil,
          optional(:open_bookings_limit) => pos_integer() | nil
        }

  @doc "The earliest class start that can count against any limit of a class at `slot_at`."
  def counted_from(%DateTime{} = slot_at, %DateTime{} = now, zone) do
    week_start = slot_at |> ZonedTime.local_date(zone) |> monday() |> ZonedTime.start_of_day(zone)
    if DateTime.compare(week_start, now) == :lt, do: week_start, else: now
  end

  @doc """
  `:ok`, or `{:error, code, %{limit: n}}` with code
  `:booking_daily_limit_reached`, `:booking_weekly_limit_reached` or
  `:booking_open_limit_reached`.
  """
  def check(limits, %DateTime{} = slot_at, booked, %DateTime{} = now, zone)
      when is_list(booked) do
    day = ZonedTime.local_date(slot_at, zone)
    week = monday(day)
    local = Enum.map(booked, &{&1, ZonedTime.local_date(&1, zone)})

    daily = Enum.count(local, fn {_at, date} -> date == day end)
    weekly = Enum.count(local, fn {_at, date} -> monday(date) == week end)
    open = Enum.count(local, fn {at, _date} -> DateTime.compare(at, now) == :gt end)

    cond do
      reached?(limits[:daily_booking_limit], daily) ->
        {:error, :booking_daily_limit_reached, %{limit: limits[:daily_booking_limit]}}

      reached?(limits[:weekly_booking_limit], weekly) ->
        {:error, :booking_weekly_limit_reached, %{limit: limits[:weekly_booking_limit]}}

      reached?(limits[:open_bookings_limit], open) ->
        {:error, :booking_open_limit_reached, %{limit: limits[:open_bookings_limit]}}

      true ->
        :ok
    end
  end

  @doc "Whether any limit is set."
  def any?(limits),
    do:
      Enum.any?(
        [:daily_booking_limit, :weekly_booking_limit, :open_bookings_limit],
        &is_integer(limits[&1])
      )

  defp reached?(limit, count) when is_integer(limit), do: count >= limit
  defp reached?(_limit, _count), do: false

  defp monday(%Date{} = date), do: Date.add(date, 1 - Date.day_of_week(date))
end
