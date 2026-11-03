defmodule Palee.Scheduling.Domain.BookingInviteEmailTest do
  use ExUnit.Case, async: true

  alias Palee.Scheduling.Domain.{BookingInviteEmail, ICalendar}

  describe "decide/2 (ADR-392)" do
    test "a confirmed seat in a live class is booked; a request or a waiting place is not" do
      assert {:send, :booked} = BookingInviteEmail.decide(:booked, %{status: :approved})
      assert :skip = BookingInviteEmail.decide(:booked, %{status: :pending})
      assert :skip = BookingInviteEmail.decide(:booked, %{status: "waitlisted"})

      assert :skip =
               BookingInviteEmail.decide(:booked, %{status: :approved, class_cancelled?: true})

      # Confirmed again after an invite went out: an update, not a second booking.
      assert {:send, :changed} =
               BookingInviteEmail.decide(:booked, %{status: :approved, sent_before?: true})
    end

    test "a moved class updates confirmed seats only" do
      assert {:send, :changed} = BookingInviteEmail.decide(:moved, %{status: :approved})
      assert :skip = BookingInviteEmail.decide(:moved, %{status: :pending})
      assert :skip = BookingInviteEmail.decide(:moved, %{status: :approved, class_cancelled?: true})
    end

    test "a cancellation reaches a seat that was confirmed or had its invite" do
      assert {:send, :cancelled} =
               BookingInviteEmail.decide(:cancelled, %{previous_status: :approved})

      assert {:send, :cancelled} =
               BookingInviteEmail.decide(:cancelled, %{previous_status: :pending, sent_before?: true})

      assert :skip = BookingInviteEmail.decide(:cancelled, %{previous_status: :pending})
      assert :skip = BookingInviteEmail.decide(:cancelled, %{previous_status: "waitlisted"})
      assert :skip = BookingInviteEmail.decide(:cancelled, %{})
      assert :skip = BookingInviteEmail.decide(:other, %{status: :approved})
    end
  end

  describe "moved?/2" do
    @before %{scheduled_at: ~U[2026-11-10 17:00:00Z], duration_minutes: 60, location_id: "a"}

    test "another start, length or branch moves the class" do
      refute BookingInviteEmail.moved?(@before, Map.put(@before, :capacity, 30))
      # The same moment in another offset is the same start.
      same = DateTime.shift_zone!(@before.scheduled_at, "Europe/Athens")
      refute BookingInviteEmail.moved?(@before, %{@before | scheduled_at: same})

      assert BookingInviteEmail.moved?(@before, %{@before | scheduled_at: ~U[2026-11-10 18:00:00Z]})
      assert BookingInviteEmail.moved?(@before, %{@before | duration_minutes: 45})
      assert BookingInviteEmail.moved?(@before, %{@before | location_id: "b"})
    end
  end

  describe "keys and SEQUENCE" do
    test "one key per kind and state; a repeat of the same state is already sent" do
      key = BookingInviteEmail.idempotency_key("b1", :booked, 100, 100)
      assert key == "booking_invite:b1:booked:100:100"
      assert String.starts_with?(key, BookingInviteEmail.key_prefix("b1"))

      assert BookingInviteEmail.already_sent?([key], "b1", :booked, 100)
      refute BookingInviteEmail.already_sent?([key], "b1", :changed, 100)
      refute BookingInviteEmail.already_sent?([key], "b1", :booked, 101)
      refute BookingInviteEmail.already_sent?([key], "b2", :booked, 100)
    end

    test "SEQUENCE stays above every invite already emailed" do
      assert BookingInviteEmail.sequence(100, []) == 100
      assert BookingInviteEmail.sequence(100, ["booking_invite:b1:booked:100:100"]) == 101

      assert BookingInviteEmail.sequence(500, [
               "booking_invite:b1:booked:100:100",
               "booking_invite:b1:changed:100:101"
             ]) == 500

      assert BookingInviteEmail.sequence(100, ["booking_invite:b1:changed:100:101", "junk"]) ==
               102
    end
  end

  describe "ICalendar invite parties" do
    test "an emailed invite names the box as organizer and the person as attendee" do
      ics =
        ICalendar.render(
          [
            %{
              uid: "class-1@palee",
              title: "Class: CrossFit",
              description: "Booked",
              starts_at: ~U[2026-11-02 17:00:00Z],
              ends_at: ~U[2026-11-02 18:00:00Z],
              status: "CONFIRMED",
              sequence: 7,
              organizer: %{name: ~s(Box "Alpha"), email: "no-reply@palee.app"},
              attendee: %{name: "Μαρία", email: "maria@example.com"}
            }
          ],
          ~U[2026-10-31 12:00:00Z],
          method: "REQUEST"
        )
        |> String.replace("\r\n ", "")

      assert ics =~ "METHOD:REQUEST"
      # Quotes cannot appear inside a quoted parameter.
      assert ics =~ ~s(ORGANIZER;CN="Box Alpha":mailto:no-reply@palee.app)

      assert ics =~
               ~s(ATTENDEE;CN="Μαρία";ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;RSVP=FALSE:mailto:maria@example.com)

      assert ics =~ "SEQUENCE:7"
    end

    test "the feed and the download name no parties" do
      ics =
        ICalendar.render(
          [
            %{
              uid: "class-1@palee",
              title: "Class",
              description: "",
              starts_at: ~U[2026-11-02 17:00:00Z],
              ends_at: ~U[2026-11-02 18:00:00Z],
              attendee: %{name: "x", email: nil}
            }
          ],
          ~U[2026-10-31 12:00:00Z]
        )

      refute ics =~ "ORGANIZER"
      refute ics =~ "ATTENDEE"
    end
  end
end
