defmodule Palee.Scheduling.Domain.VisitBadgesAndCalendarTest do
  use ExUnit.Case, async: true

  alias Palee.Coaching.Domain.CoachNotePolicy
  alias Palee.Scheduling.Domain.{ICalendar, VisitBadges}

  describe "VisitBadges" do
    test "a first visit, and how the person came" do
      assert VisitBadges.badges(%{box_visits: 0, roles: ["member"]}) == ["first_visit"]

      assert VisitBadges.badges(%{
               box_visits: 0,
               referral: %{event_id: "e", referrer_user_id: nil}
             }) ==
               ["first_visit", "came_via_event"]

      assert VisitBadges.badges(%{
               box_visits: 0,
               referral: %{event_id: nil, referrer_user_id: "u"}
             }) ==
               ["first_visit", "came_via_referral"]

      # How someone came only matters on their first visit.
      assert VisitBadges.badges(%{box_visits: 3, type_visits: 1, referral: %{event_id: "e"}}) ==
               []
    end

    test "first time in this kind of class, guest, trial and guest passes" do
      assert VisitBadges.badges(%{box_visits: 5, type_visits: 0}) == ["first_in_class_type"]
      assert VisitBadges.badges(%{box_visits: 5, type_visits: nil}) == []

      assert VisitBadges.badges(%{box_visits: 2, roles: ["guest"]}) == ["guest"]
      # A member who is also a guest elsewhere is a member here.
      assert VisitBadges.badges(%{box_visits: 2, roles: ["member", "guest"]}) == []

      assert VisitBadges.badges(%{box_visits: 0, booking_kind: "trial"}) == [
               "first_visit",
               "trial"
             ]

      assert "brought_by_member" in VisitBadges.badges(%{box_visits: 9, guest_name: "Νίκος"})
    end
  end

  describe "ICalendar" do
    @now ~U[2026-10-31 12:00:00Z]

    test "SEQUENCE grows with the latest change and never goes below zero" do
      assert ICalendar.sequence([]) == 0
      assert ICalendar.sequence([nil, ~U[2025-01-01 00:00:00Z]]) == 0
      a = ICalendar.sequence([~U[2026-10-01 10:00:00Z]])
      b = ICalendar.sequence([~U[2026-10-01 10:00:00Z], ~U[2026-10-02 10:00:00Z]])
      assert b > a and b - a == 86_400
    end

    test "status follows the seat, and a cancelled class cancels every seat" do
      assert ICalendar.status(:approved, nil) == "CONFIRMED"
      assert ICalendar.status(:pending, nil) == "TENTATIVE"
      assert ICalendar.status(:waitlisted, nil) == "TENTATIVE"
      assert ICalendar.status(:cancelled, nil) == "CANCELLED"
      assert ICalendar.status(nil, nil) == "CANCELLED"
      assert ICalendar.status(:approved, @now) == "CANCELLED"
    end

    test "renders a seat with UID, STATUS, SEQUENCE, LOCATION and folds long lines" do
      ics =
        ICalendar.render(
          [
            %{
              uid: "class-1@palee",
              title: "Class: CrossFit",
              description: String.duplicate("Πολύ μεγάλη περιγραφή; ", 8),
              starts_at: ~U[2026-11-02 17:00:00Z],
              ends_at: ~U[2026-11-02 18:00:00Z],
              status: "CANCELLED",
              sequence: 42,
              last_modified: ~U[2026-10-30 09:00:00Z],
              location: "Box, Οδός 1, Αθήνα"
            }
          ],
          @now,
          method: "CANCEL"
        )

      assert ics =~ "METHOD:CANCEL\r\n"
      assert ics =~ "UID:class-1@palee\r\n"
      assert ics =~ "STATUS:CANCELLED\r\n"
      assert ics =~ "SEQUENCE:42\r\n"
      assert ics =~ "LAST-MODIFIED:20261030T090000Z\r\n"
      assert ics =~ "LOCATION:Box\\, Οδός 1\\, Αθήνα\r\n"
      assert ics =~ "\r\n "

      assert ics |> String.split("\r\n") |> Enum.all?(&(byte_size(&1) <= 75))
      # Unfolding gives the escaped description back.
      assert String.replace(ics, "\r\n ", "") =~ "DESCRIPTION:Πολύ μεγάλη περιγραφή\\; "
    end
  end

  describe "CoachNotePolicy (ADR-359 staff notes)" do
    @private %{coach_user_id: "coach", audience: "private"}
    @staff %{coach_user_id: "desk", audience: "staff"}

    test "a private note keeps ADR-101's readers" do
      refute CoachNotePolicy.readable?(@private, "desk", [:front_desk], true)
      assert CoachNotePolicy.readable?(@private, "owner", [:owner], false)
      refute CoachNotePolicy.readable?(@private, "admin", [:admin], false)
      assert CoachNotePolicy.logged?(@private, "owner")
    end

    test "a staff note is read by staff who see the directory, and not logged" do
      assert CoachNotePolicy.readable?(@staff, "coach", [:coach], false)
      assert CoachNotePolicy.readable?(@staff, "other-desk", [:front_desk], false)
      refute CoachNotePolicy.readable?(@staff, "cleaner", [:janitor], false)
      # ANR 2026-11-03 (v3.1 question 12): the accountant never reads staff notes.
      refute CoachNotePolicy.readable?(@staff, "books", [:accountant], false)
      refute CoachNotePolicy.readable?(@private, "books", [:accountant], true)
      refute CoachNotePolicy.readable?(@staff, "member", [:member], false)
      refute CoachNotePolicy.logged?(@staff, "coach")
      assert CoachNotePolicy.can_edit?(@staff, "desk")
      refute CoachNotePolicy.can_edit?(@staff, "coach")
    end
  end
end
