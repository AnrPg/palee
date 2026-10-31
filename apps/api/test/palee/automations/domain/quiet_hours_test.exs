defmodule Palee.Automations.Domain.QuietHoursTest do
  use ExUnit.Case, async: true

  alias Palee.Automations.Domain.QuietHours

  @athens "Europe/Athens"

  test "a moment inside the night window waits for its end on the box's clock" do
    # 23:30 in Athens (UTC+3 in summer) is 20:30 UTC.
    late = ~U[2027-07-01 20:30:00Z]
    assert QuietHours.next_allowed(late, @athens, "21:00", "09:00") == ~U[2027-07-02 06:00:00Z]

    # 07:00 Athens, before the window ends the same morning.
    early = ~U[2027-07-02 04:00:00Z]
    assert QuietHours.next_allowed(early, @athens, "21:00", "09:00") == ~U[2027-07-02 06:00:00Z]
  end

  test "a moment outside the window goes as is" do
    noon = ~U[2027-07-01 09:00:00Z]
    assert QuietHours.next_allowed(noon, @athens, "21:00", "09:00") == noon
  end

  test "a window within one day, and none at all" do
    at = ~U[2027-01-10 12:30:00Z]
    # 14:30 Athens in winter (UTC+2), quiet 14:00-16:00.
    assert QuietHours.next_allowed(at, @athens, "14:00", "16:00") == ~U[2027-01-10 14:00:00Z]
    assert QuietHours.next_allowed(at, @athens, "10:00", "10:00") == at
  end

  test "the daily send hour on the box's clock" do
    assert QuietHours.at_local_hour(~D[2027-01-10], 10, @athens) == ~U[2027-01-10 08:00:00Z]
    assert QuietHours.at_local_hour(~D[2027-07-10], 10, @athens) == ~U[2027-07-10 07:00:00Z]
  end
end
