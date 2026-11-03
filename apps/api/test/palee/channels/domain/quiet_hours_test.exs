defmodule Palee.Channels.Domain.QuietHoursTest do
  use ExUnit.Case, async: true

  alias Palee.Channels.Domain.QuietHours

  @zone "Europe/Athens"

  test "outside quiet hours a message goes at once" do
    # 12:00 in Athens (UTC+2 in winter).
    now = ~U[2026-11-10 10:00:00.000000Z]
    assert QuietHours.release_at(now, @zone, 21 * 60, 9 * 60) == now
  end

  test "late in the evening it waits for 09:00 the next morning, on the box's clock" do
    # 22:30 Athens.
    now = ~U[2026-11-10 20:30:00.000000Z]
    assert QuietHours.release_at(now, @zone, 21 * 60, 9 * 60) == ~U[2026-11-11 07:00:00Z]
  end

  test "after midnight it waits for 09:00 the same day" do
    # 03:00 Athens.
    now = ~U[2026-11-11 01:00:00.000000Z]
    assert QuietHours.release_at(now, @zone, 21 * 60, 9 * 60) == ~U[2026-11-11 07:00:00Z]
  end

  test "a window inside the day, and no window at all" do
    now = ~U[2026-11-10 12:00:00.000000Z]
    assert QuietHours.release_at(now, @zone, 13 * 60, 15 * 60) == ~U[2026-11-10 13:00:00Z]
    assert QuietHours.release_at(now, @zone, nil, nil) == now
  end

  test "only marketing waits for quiet hours; service messages always go (ADR-390)" do
    assert QuietHours.applies?("marketing")
    refute QuietHours.applies?("service")
    refute function_exported?(QuietHours, :defaults, 0)
  end

  test "parse and format" do
    assert {:ok, {1260, 540}} = QuietHours.parse("21:00", "09:00")
    assert {:ok, {nil, nil}} = QuietHours.parse(nil, nil)
    assert {:error, :invalid_quiet_hours} = QuietHours.parse("25:00", "09:00")
    assert {:error, :invalid_quiet_hours} = QuietHours.parse("21:00", nil)
    assert QuietHours.format(540) == "09:00"
    assert QuietHours.format(nil) == nil
  end
end
