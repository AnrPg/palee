defmodule Palee.Application.AdminRemoveAttendance do
  @moduledoc """
  Staff take back a «Ήρθε» from the class page: a tap by mistake, or a
  member who checked in but left. The attendance record goes, however it was
  recorded (staff, the member's own check-in, a scan); the booking stays, so
  the person is booked again as before.

  The visit: a «Ήρθε» recorded by staff finalized the booking's reservation;
  that finalize is undone so the visit is held again and a later cancellation
  still returns it. A trial seat goes back from attended to booked. Open
  class pages, box screens and Wallet cards are told (the class only, never
  who, on the schedule topic).
  """

  alias Palee.Application.{
    BookingEntitlement,
    CheckInActions,
    ClassLocation,
    ScheduleRealtime,
    TrackAnalyticsEvent
  }

  alias Palee.Scheduling
  alias Palee.Scheduling.Domain.AttendancePolicy

  def call(%{organization_id: _} = context, slot_id, user_id, admin_id) do
    with :ok <- ClassLocation.authorize_class(context, slot_id),
         {:ok, attendance} <- attendance(context, slot_id, user_id),
         :ok <- AttendancePolicy.can_remove_admin_attendance?(attendance),
         {:ok, _transition} <- reopen_visit(context, attendance),
         {:ok, _deleted} <- Scheduling.delete_attendance(context, attendance.id) do
      CheckInActions.undo_trial_attend(context, attendance.booking_id, nil)

      TrackAnalyticsEvent.call("class_attendance_removed", context, attendance, %{
        metadata: %{member_id: user_id, removed_by_id: admin_id}
      })

      announce_removal(attendance)
      {:ok, attendance}
    end
  end

  def call(_context, _slot_id, _user_id, _admin_id), do: {:error, :organization_context_required}

  defp attendance(context, slot_id, user_id) do
    case Scheduling.get_attendance_for_user_class(context, user_id, slot_id) do
      nil -> {:error, :not_found}
      attendance -> {:ok, attendance}
    end
  end

  # Only the finalize AdminRecordAttendance wrote for this record; a scan or
  # self check-in never finalized, so there is nothing to undo then.
  defp reopen_visit(context, attendance) do
    allowance =
      case Scheduling.get_approved_booking_for_class(
             context,
             attendance.user_id,
             attendance.scheduled_class_id
           ) do
        nil -> :class_visits
        booking -> BookingEntitlement.allowance(booking)
      end

    BookingEntitlement.reopen(
      context,
      attendance.user_id,
      attendance.scheduled_class_id,
      allowance,
      %{idempotency_key: "attendance-finalized:#{attendance.id}"}
    )
  end

  defp announce_removal(attendance) do
    ScheduleRealtime.broadcast("attendance_removed", %{
      organization_id: attendance.organization_id,
      slot_id: attendance.scheduled_class_id
    })

    Palee.DomainEvents.publish(:attendance_removed, %{
      organization_id: attendance.organization_id,
      scheduled_class_id: attendance.scheduled_class_id,
      user_id: attendance.user_id,
      booking_id: attendance.booking_id,
      at: DateTime.utc_now()
    })
  end
end
