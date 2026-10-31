defmodule Palee.Scheduling.Domain.BookingLimitsTest do
  use ExUnit.Case, async: true

  alias Palee.Scheduling.Domain.BookingLimits

  @zone "Europe/Athens"
  # Wednesday 2027-05-05, 18:00 in Athens (UTC+3).
  @slot ~U[2027-05-05 15:00:00Z]
  @now ~U[2027-05-03 08:00:00Z]

  test "no limits is always fine" do
    assert BookingLimits.check(%{}, @slot, [@slot, @slot], @now, @zone) == :ok
    refute BookingLimits.any?(%{daily_booking_limit: nil})
    assert BookingLimits.any?(%{weekly_booking_limit: 2})
  end

  test "the daily limit counts the class's gym-local day" do
    limits = %{daily_booking_limit: 1}
    # 23:30 Athens on the 5th is 20:30 UTC: the same local day.
    same_day = ~U[2027-05-05 20:30:00Z]
    # 00:30 Athens on the 6th is 21:30 UTC on the 5th: the next local day.
    next_day = ~U[2027-05-05 21:30:00Z]

    assert {:error, :booking_daily_limit_reached, %{limit: 1}} =
             BookingLimits.check(limits, @slot, [same_day], @now, @zone)

    assert BookingLimits.check(limits, @slot, [next_day], @now, @zone) == :ok
  end

  test "the weekly limit counts Monday to Sunday, gym-local" do
    limits = %{weekly_booking_limit: 2}
    monday = ~U[2027-05-03 06:00:00Z]
    sunday = ~U[2027-05-09 18:00:00Z]
    next_monday = ~U[2027-05-10 06:00:00Z]

    assert {:error, :booking_weekly_limit_reached, %{limit: 2}} =
             BookingLimits.check(limits, @slot, [monday, sunday], @now, @zone)

    assert BookingLimits.check(limits, @slot, [monday, next_monday], @now, @zone) == :ok
  end

  test "the open limit counts upcoming bookings only" do
    limits = %{open_bookings_limit: 2}
    past = ~U[2027-05-02 06:00:00Z]
    later = ~U[2027-05-20 06:00:00Z]

    assert BookingLimits.check(limits, @slot, [past, later], @now, @zone) == :ok

    assert {:error, :booking_open_limit_reached, %{limit: 2}} =
             BookingLimits.check(limits, @slot, [later, @slot], @now, @zone)
  end

  test "counting starts at the week's start or now, whichever is first" do
    assert BookingLimits.counted_from(@slot, @now, @zone) == ~U[2027-05-02 21:00:00Z]
    early_now = ~U[2027-04-20 08:00:00Z]
    assert BookingLimits.counted_from(@slot, early_now, @zone) == early_now
  end
end
