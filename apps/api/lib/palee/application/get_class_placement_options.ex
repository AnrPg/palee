defmodule Palee.Application.GetClassPlacementOptions do
  @moduledoc """
  What staff can choose in «Κλείσιμο ή μετακίνηση μαθήματος» on a member's
  profile (ADR-232): the member's upcoming bookings that can be moved, and
  the upcoming classes of the staff member's branches, each with the reason
  it cannot take the member now (or nil), decided by the same rules as
  `PlaceMemberInClass`. The reasons are the booking error codes, so the
  dialog explains a disabled class in the words it would show for the error.

  Cancelled classes are left out. The member's package is checked the way a
  booking checks it (covers the class, a visit left, not frozen), without
  reserving anything. A class refused only for
  `finance_allowance_exhausted` can still take the member in a move, since
  the move returns the old booking's visit first; the dialog allows it then.

  ADR-790: a full class the member could wait for comes with `waitlist:
  true` and `waitlist_place`, the place «Στο τέλος» would give them; staff
  then put them on its waitlist (`PlaceMemberOnWaitlist`). A move never goes
  to a waitlist, so the dialog keeps those classes closed while moving.
  `slot_id:` limits the answer to that one class (the class page's «+
  Προσθήκη»), however far away it is.
  """

  alias Palee.{Finance, Identity, Organizations, Scheduling}
  alias Palee.Application.{BookingTerms, ClassPlacementAccess, PlaceMemberInClass}
  alias Palee.Scheduling.Domain.BookingPolicy

  @lookahead_days 30
  @movable_statuses [:pending, :approved]

  def call(context, user_id, opts \\ [])

  def call(%{organization_id: organization_id} = context, user_id, opts)
      when is_binary(organization_id) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         :ok <- ClassPlacementAccess.authorize(context, user.id, Keyword.get(opts, :slot_id)),
         :ok <- PlaceMemberInClass.require_member(context, user.id),
         {:ok, window_end, only} <- window(context, Keyword.get(opts, :slot_id)) do
      now = DateTime.utc_now()

      slots =
        context
        |> Scheduling.get_calendar_week(%{
          start_at: now,
          end_at: window_end,
          class_type_ids: [],
          include_drafts: true
        })
        |> Enum.filter(
          &(DateTime.compare(&1.scheduled_at, now) == :gt and is_nil(Map.get(&1, :cancelled_at)) and
              (is_nil(only) or &1.id == only))
        )
        |> then(&Organizations.filter_by_location_scope(context, &1))
        |> Enum.sort_by(& &1.scheduled_at, DateTime)

      {booked, open} = Enum.split_with(slots, &movable_booking(&1, user.id))

      {:ok,
       %{
         timezone: Organizations.organization_timezone(organization_id),
         lookahead_days: @lookahead_days,
         bookings: Enum.map(booked, &booking_option(&1, user.id)),
         classes: class_options(context, open, user, now)
       }}
    end
  end

  def call(_context, _user_id, _opts), do: {:error, :organization_context_required}

  # ADR-790: the class page asks about one class, which may be further away
  # than the profile's 30 days.
  defp window(_context, nil), do: {:ok, lookahead_end(), nil}

  defp window(context, slot_id) when is_binary(slot_id) do
    case Scheduling.get_slot(context, slot_id) do
      nil ->
        {:error, :not_found}

      slot ->
        later = DateTime.add(slot.scheduled_at, 60, :second)
        default = lookahead_end()

        {:ok, if(DateTime.compare(later, default) == :gt, do: later, else: default), slot.id}
    end
  end

  defp lookahead_end, do: DateTime.add(DateTime.utc_now(), @lookahead_days * 86_400, :second)

  defp movable_booking(slot, user_id) do
    Enum.find(slot.bookings, fn booking ->
      booking.user_id == user_id and booking.status in @movable_statuses and
        Map.get(booking, :kind, "member") == "member"
    end)
  end

  defp booking_option(slot, user_id) do
    booking = movable_booking(slot, user_id)

    %{
      booking_id: booking.id,
      slot_id: slot.id,
      name: slot.name,
      scheduled_at: slot.scheduled_at,
      status: booking.status
    }
  end

  defp class_options(_context, [], _user, _now), do: []

  defp class_options(context, slots, user, now) do
    {open, closed} =
      slots
      |> Enum.map(&policy(&1, user.id, now))
      |> Enum.split_with(fn {_slot, reason, _mode} -> is_nil(reason) end)

    requests =
      Enum.map(open, fn {slot, nil, _mode} ->
        slot
        |> BookingPolicy.entitlement_request()
        |> Map.merge(%{
          actor_role: user.role,
          starts_at: slot.scheduled_at,
          location_id: Map.get(slot, :location_id)
        })
      end)

    package_reasons =
      context
      |> Finance.check_entitlements(user.id, requests)
      |> Enum.map(fn
        :ok -> nil
        {:error, reason} -> Atom.to_string(reason)
      end)

    checked =
      Enum.zip_with(open, package_reasons, fn {slot, nil, mode}, reason ->
        {slot, reason, mode}
      end)

    (checked ++ closed)
    |> Enum.sort_by(fn {slot, _reason, _mode} -> slot.scheduled_at end, DateTime)
    |> Enum.map(fn {slot, reason, mode} ->
      %{
        slot_id: slot.id,
        name: slot.name,
        scheduled_at: slot.scheduled_at,
        duration_minutes: slot.duration_minutes,
        capacity: slot.capacity,
        spots_remaining: max(slot.spots_remaining || 0, 0),
        blocked_reason: reason,
        waitlist: mode == :waitlist,
        waitlist_place: waitlist_place(context, user.id, slot, mode)
      }
    end)
  end

  # ADR-790: a full class takes the member on its waitlist instead.
  defp policy(slot, user_id, now) do
    case BookingPolicy.can_book?(slot, user_id: user_id, now: now) do
      :ok ->
        {slot, nil, :book}

      {:error, :slot_full} ->
        case BookingPolicy.can_join_waitlist?(slot, user_id: user_id, now: now) do
          :ok -> {slot, nil, :waitlist}
          {:error, reason} -> {slot, Atom.to_string(reason), :book}
        end

      {:error, reason} ->
        {slot, Atom.to_string(reason), :book}
    end
  end

  # Where «Στο τέλος» would put the member (package priority counts).
  defp waitlist_place(context, user_id, slot, :waitlist) do
    priority = BookingTerms.for_slot(context, user_id, slot).waitlist_priority

    slot.bookings
    |> Enum.filter(&(&1.status == :waitlisted))
    |> BookingPolicy.waitlist_place(:end, priority)
  end

  defp waitlist_place(_context, _user_id, _slot, _mode), do: nil
end
