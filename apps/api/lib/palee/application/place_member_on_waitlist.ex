defmodule Palee.Application.PlaceMemberOnWaitlist do
  @moduledoc """
  ADR-790 (ANR picks 1C, 2B, α–ε, 2026-11-28): staff put a member on a full
  class's waitlist, from the class page («+ Προσθήκη») or from the member's
  profile («Κράτηση ή μετακίνηση»).

    * Who: the box's owner and office staff for classes of their own
      branches (ADR-186), and coaches for the classes they run
      (`ClassPlacementAccess`), the same as `PlaceMemberInClass`.
    * For whom: active members of the box only (not online-programming
      athletes or followers).
    * The class: future, open, published and full. A class with room is
      booked with `PlaceMemberInClass` instead, so the caller is told
      `:slot_not_full`.
    * The package: checked as when staff place the member in a class (covers
      the class, a visit left, not frozen), without reserving anything; the
      package rule of ADR-633 does not apply (staff decide).
    * Position (`position`): `"end"` (default) takes the place the member
      would take by joining themselves (package priority still counts);
      `"first"` puts them ahead of everyone, the latest «first» leading.
    * When a place opens, the entry is promoted like any other but approved
      at once (`waitlisted_by_id` set), never waiting for approval.

  The member hears it (bell and push) with their place in line; staff screens
  refresh over the schedule topic.
  """

  alias Palee.Application.{BookingTerms, ClassPlacementAccess, GoLive, PlaceMemberInClass}
  alias Palee.Application.ScheduleRealtime
  alias Palee.{Finance, Identity, Notifications, Scheduling}
  alias Palee.Scheduling.Domain.BookingPolicy

  @positions %{"end" => :end, "first" => :first}

  def call(context, user_id, params) do
    slot_id = value(params, :slot_id)
    now = DateTime.utc_now()

    with {:ok, position} <- position(value(params, :position)),
         %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         :ok <- ClassPlacementAccess.authorize(context, user.id, slot_id),
         :ok <- PlaceMemberInClass.require_member(context, user.id),
         %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- GoLive.check_booking(context, user.id),
         :ok <- BookingPolicy.can_join_waitlist?(slot, user_id: user.id, now: now),
         request = BookingPolicy.entitlement_request(slot),
         :ok <- package_covers(context, user, slot, request),
         terms = BookingTerms.for_slot(context, user.id, slot),
         {:ok, entry} <-
           Scheduling.join_waitlist(context, user.id, slot.id, %{
             waitlist_priority: terms.waitlist_priority,
             entitlement_allowance: BookingPolicy.booking_allowance(request),
             waitlisted_by_id: context.user_id,
             waitlist_front_at: if(position == :first, do: now)
           }) do
      place = place_of(context, slot.id, entry.id)
      announce(context, slot, entry, place)
      {:ok, %{booking: entry, waitlist_position: place}}
    end
  end

  @doc "The positions staff may choose, as the API spells them."
  def positions, do: Map.keys(@positions)

  defp position(nil), do: {:ok, :end}
  defp position(""), do: {:ok, :end}

  defp position(value) when is_binary(value) do
    case Map.fetch(@positions, value) do
      {:ok, position} -> {:ok, position}
      :error -> {:error, :invalid_waitlist_position}
    end
  end

  defp position(_value), do: {:error, :invalid_waitlist_position}

  # The same dry run as the profile's class choices (GetClassPlacementOptions).
  defp package_covers(context, user, slot, request) do
    check =
      Map.merge(request, %{
        actor_role: user.role,
        starts_at: slot.scheduled_at,
        location_id: Map.get(slot, :location_id)
      })

    case Finance.check_entitlements(context, user.id, [check]) do
      [:ok] -> :ok
      [{:error, reason}] -> {:error, reason}
    end
  end

  defp place_of(context, slot_id, entry_id) do
    context
    |> Scheduling.list_waitlist(slot_id)
    |> BookingPolicy.waitlist_order()
    |> Enum.find_index(&(&1.id == entry_id))
    |> case do
      nil -> nil
      index -> index + 1
    end
  end

  defp announce(context, slot, entry, place) do
    ScheduleRealtime.broadcast("booking_waitlisted", entry)

    Notifications.process_event("booking_waitlisted_by_staff", %{
      user_id: entry.user_id,
      organization_id: context.organization_id,
      booking_id: entry.id,
      scheduled_class_id: slot.id,
      class_name: slot.name,
      class_starts_at: slot.scheduled_at,
      position: place
    })

    :ok
  end

  defp value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
