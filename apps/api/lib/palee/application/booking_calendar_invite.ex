defmodule Palee.Application.BookingCalendarInvite do
  @moduledoc """
  ADR-359 (CP-E4): one booking as an `.ics` invite («Προσθήκη στο
  ημερολόγιο»). It carries the same UID as the person's calendar feed
  (`class-<class id>@palee`) and the same SEQUENCE rule, so importing it
  and later subscribing never shows the class twice, and importing it again
  after a change updates the entry. A cancelled seat or class comes as
  `METHOD:CANCEL`, which removes it from the calendar it was imported into.

  Only the person who booked reads it.
  """

  alias Palee.Application.GetCalendarFeed
  alias Palee.{Identity, Scheduling}
  alias Palee.Scheduling.Domain.ICalendar

  def call(context, booking_id, now \\ nil)

  def call(%{organization_id: org, user_id: user_id} = context, booking_id, now)
      when is_binary(org) and is_binary(user_id) do
    now = now || DateTime.utc_now()

    with %{} = booking <-
           Scheduling.get_booking(context, booking_id) || {:error, :booking_not_found},
         true <- booking.user_id == user_id || {:error, :booking_not_found},
         %{} <- booking.scheduled_class || {:error, :booking_not_found},
         %{} = user <- Identity.find_by_id(user_id) || {:error, :booking_not_found} do
      {:ok, build(context, booking, user, now)}
    end
  end

  def call(_context, _booking_id, _now), do: {:error, :organization_context_required}

  @doc """
  The invite of `booking` (its `scheduled_class` preloaded) for `user`, in
  the user's locale. Options (ADR-392, the emailed invite): `invite: true`
  sends `METHOD:REQUEST` instead of `PUBLISH` and names the box as
  `ORGANIZER` (`organizer: %{name, email}`) and the person as `ATTENDEE`;
  `locations` skips reading the branches again. A cancelled seat or class is
  always `METHOD:CANCEL`. Answers `%{filename, method, ics, event}`.
  """
  def build(context, booking, user, now, opts \\ []) do
    slot = booking.scheduled_class
    locale = user.preferred_locale || "en"
    slot = Map.put(slot, :bookings, [booking])
    locations = Keyword.get_lazy(opts, :locations, fn -> GetCalendarFeed.locations(context) end)
    event = GetCalendarFeed.seat_event(slot, user, locale, locations)
    invite? = Keyword.get(opts, :invite, false)

    method =
      cond do
        event.status == "CANCELLED" -> "CANCEL"
        invite? -> "REQUEST"
        true -> "PUBLISH"
      end

    event =
      if invite?,
        do:
          Map.merge(event, %{
            organizer: Keyword.get(opts, :organizer),
            attendee: %{name: Map.get(user, :display_name), email: Map.get(user, :email)}
          }),
        else: event

    %{
      filename: "palee-#{Date.to_iso8601(DateTime.to_date(slot.scheduled_at))}.ics",
      method: method,
      event: event,
      ics: ICalendar.render([event], now, method: method)
    }
  end
end
