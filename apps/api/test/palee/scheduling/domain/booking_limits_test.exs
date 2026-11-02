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
    assert BookingLimits.any?(%{open_bookings_limit: 2})
    # ADR-383: there is no weekly limit; the package's visits per week cover it.
    refute BookingLimits.any?(%{weekly_booking_limit: 2})
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

  test "a weekly limit is not a booking limit (ADR-383)" do
    monday = ~U[2027-05-03 06:00:00Z]
    sunday = ~U[2027-05-09 18:00:00Z]

    assert BookingLimits.check(%{weekly_booking_limit: 1}, @slot, [monday, sunday], @now, @zone) ==
             :ok
  end

  test "the open limit counts upcoming bookings only" do
    limits = %{open_bookings_limit: 2}
    past = ~U[2027-05-02 06:00:00Z]
    later = ~U[2027-05-20 06:00:00Z]

    assert BookingLimits.check(limits, @slot, [past, later], @now, @zone) == :ok

    assert {:error, :booking_open_limit_reached, %{limit: 2}} =
             BookingLimits.check(limits, @slot, [later, @slot], @now, @zone)
  end

  test "counting starts at the class's gym-local day or now, whichever is first" do
    assert BookingLimits.counted_from(@slot, @now, @zone) == @now
    same_day_now = ~U[2027-05-05 10:00:00Z]
    assert BookingLimits.counted_from(@slot, same_day_now, @zone) == ~U[2027-05-04 21:00:00Z]
  end
end
