defmodule Palee.Application.BookingInviteEmails do
  @moduledoc """
  ADR-392 («Email κράτησης με ημερολόγιο»): one email through the outbox
  (ADR-203) when a seat in a class is confirmed, when its class moves, and
  when the seat or the class is cancelled, with the class's calendar invite
  attached as `text/calendar`: `METHOD:REQUEST` with the same UID as the
  person's feed and the «Προσθήκη στο ημερολόγιο» download, `METHOD:CANCEL`
  once cancelled, SEQUENCE growing with every change (ADR-359). Calendars
  that already hold the class from the feed merge it by UID.

  A domain event handler (ADR-144): it runs after the booking's own write
  and never fails or blocks it. It reacts to `:booking_made` and
  `:booking_confirmed` (a seat confirmed now), `:class_moved` (another
  start, length or branch) and `:booking_cancelled` (by the person, by the
  box, or with its class). `Scheduling.Domain.BookingInviteEmail` decides
  what to send; the person's switch (category `bookings`, channel `email`,
  on by default) and the outbox's own gates (demo box, suppressed or
  unsubscribed address, throttle, budget) decide whether it goes.
  """

  @behaviour Palee.DomainEvents.Handler

  require Logger

  alias Palee.Application.{BookingCalendarInvite, GetCalendarFeed, PublicURL}
  alias Palee.{Email, Identity, Notifications, Organizations, Scheduling}
  alias Palee.Scheduling.Domain.BookingInviteEmail

  @impl true
  def handle_event(event, %{organization_id: org, booking_id: booking_id} = payload)
      when event in [:booking_made, :booking_confirmed] and is_binary(org) and
             is_binary(booking_id) do
    context = %{organization_id: org}
    deliver(context, Scheduling.get_booking(context, booking_id), :booked, payload)
  end

  # A withdrawn seat's row is gone (the visit's ledger keeps its history), so
  # the cancelled seat is rebuilt from the event: its class still exists.
  def handle_event(
        :booking_cancelled,
        %{organization_id: org, booking_id: booking_id, user_id: user_id} = payload
      )
      when is_binary(org) and is_binary(booking_id) and is_binary(user_id) do
    context = %{organization_id: org}

    booking =
      case Scheduling.get_slot(context, Map.get(payload, :scheduled_class_id)) do
        %{} = slot ->
          %{
            id: booking_id,
            user_id: user_id,
            status: :cancelled,
            guest_name: Map.get(payload, :guest_name),
            updated_at: Map.get(payload, :at) || DateTime.utc_now(),
            scheduled_class: slot
          }

        _missing ->
          nil
      end

    deliver(context, booking, :cancelled, payload)
  end

  def handle_event(:class_moved, %{organization_id: org, scheduled_class_id: slot_id} = payload)
      when is_binary(org) and is_binary(slot_id) do
    context = %{organization_id: org}

    case Scheduling.get_slot(context, slot_id) do
      %{bookings: bookings} when is_list(bookings) ->
        bookings
        |> Enum.filter(&(to_string(&1.status) == "approved"))
        |> Enum.each(&deliver(context, Scheduling.get_booking(context, &1.id), :moved, payload))

      _missing ->
        :ok
    end
  end

  def handle_event(_event, _payload), do: :ok

  @doc false
  def deliver(context, booking, trigger, payload) do
    with %{} <- booking,
         %{} = slot <- booking.scheduled_class,
         true <- blank?(Map.get(booking, :guest_name)),
         %{email: email} = user when is_binary(email) <- Identity.find_by_id(booking.user_id),
         true <- Notifications.channel_enabled?(user.id, "bookings", "email"),
         sent = sent_keys(booking.id),
         {:send, kind} <- decide(trigger, booking, slot, payload, sent) do
      send_invite(context, booking, user, kind, sent, Map.get(payload, :at))
    else
      _nothing_to_send -> :ok
    end
  end

  defp decide(trigger, booking, slot, payload, sent_keys) do
    BookingInviteEmail.decide(trigger, %{
      status: booking.status,
      previous_status: Map.get(payload, :previous_status),
      class_cancelled?: not is_nil(Map.get(slot, :cancelled_at)),
      sent_before?: sent_keys != []
    })
  end

  # The idempotency keys of the invites of this booking already emailed.
  defp sent_keys(booking_id) do
    booking_id
    |> BookingInviteEmail.key_prefix()
    |> Email.list_by_idempotency_prefix()
    |> Enum.map(& &1.idempotency_key)
  end

  defp send_invite(%{organization_id: org} = context, booking, user, kind, sent, at) do
    now = at || DateTime.utc_now()
    business = organization_name(org)
    organizer = %{name: business, email: mail_from_address()}

    invite =
      BookingCalendarInvite.build(context, booking, user, now,
        invite: true,
        organizer: organizer,
        sequence: &BookingInviteEmail.sequence(&1, sent)
      )

    if BookingInviteEmail.already_sent?(sent, booking.id, kind, invite.derived_sequence),
      do: :ok,
      else: enqueue(org, booking, user, kind, invite, business)
  end

  defp enqueue(org, booking, user, kind, invite, business) do
    slot = booking.scheduled_class

    assigns = %{
      kind: kind,
      business: business,
      class_name: GetCalendarFeed.class_name(slot),
      starts_at: slot.scheduled_at,
      time_zone: Organizations.organization_timezone(org),
      location: Map.get(invite.event, :location),
      url: PublicURL.base_url() <> "/box/schedule?open_slot=#{slot.id}"
    }

    attachment = %{
      filename: invite.filename,
      content_type: "text/calendar; method=#{invite.method}; charset=UTF-8",
      data: invite.ics
    }

    key =
      BookingInviteEmail.idempotency_key(
        booking.id,
        kind,
        invite.derived_sequence,
        invite.event.sequence
      )

    case Email.enqueue(:booking_invite, user.email, assigns,
           locale: user.preferred_locale || "en",
           login_id: Map.get(user, :login_id),
           user_id: user.id,
           organization_id: org,
           idempotency_key: key,
           attachments: [attachment]
         ) do
      {:ok, _message} ->
        :ok

      {:error, reason} ->
        Logger.info("booking invite email not queued booking=#{booking.id} reason=#{inspect(reason)}")

        :ok
    end
  end

  defp organization_name(org) do
    case Organizations.get_by_id(org) do
      %{name: name} when is_binary(name) -> name
      _missing -> ""
    end
  end

  defp mail_from_address,
    do: :palee |> Application.fetch_env!(:mail_from) |> Keyword.fetch!(:address)

  defp blank?(value), do: value in [nil, ""]
end
