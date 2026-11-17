defmodule Palee.Application.RevokeAccess do
  @moduledoc """
  A client lost their access to the box (their subscription ran out, a
  payment stayed overdue, or staff marked them as gone today): their
  upcoming class bookings are cancelled, the places and class allowances
  are released, and they hear about it (`access_ended`).
  """

  alias Palee.{Finance, Notifications, Scheduling}

  @doc """
  `lost` carries the client's `user_id`, `membership_id` and the `status`
  that ended their access (`"blocked"` means an overdue payment).
  """
  def call(context, %{user_id: user_id} = lost) do
    cancelled = cancel_upcoming_bookings(context, user_id)

    Notifications.process_event("access_ended", %{
      user_id: user_id,
      membership_id: lost.membership_id,
      reason: if(lost.status == "blocked", do: "overdue_payment", else: "subscription_ended"),
      cancelled_bookings: cancelled
    })
  end

  @doc """
  Cancels the person's upcoming class bookings and gives back the places and
  class allowances they used; returns how many were cancelled (ADR-660 uses
  it when staff remove a package).
  """
  def cancel_upcoming_bookings(context, user_id) do
    case Scheduling.cancel_active_future_bookings_for_user(context, user_id) do
      {:ok, release_facts} ->
        Enum.each(release_facts, &release_class_visit(context, &1))
        length(release_facts)

      _error ->
        0
    end
  end

  defp release_class_visit(context, fact) do
    Finance.release_entitlement_source(
      context,
      fact.user_id,
      "scheduling",
      fact.scheduled_class_id,
      :class_visits,
      %{
        reason: "Access ended",
        idempotency_key: "access-ended-booking-release:#{fact.booking_id}"
      }
    )
  end
end
