defmodule Palee.Application.EventSms do
  @moduledoc """
  SMS about an event of a box or an organiser (product owner, 2026-11-02).

  Saying «Θα έρθω» may carry the person's mobile number and their «yes» to
  SMS about the event (`sms_consent`): the number and a `service` SMS
  consent are recorded with the event's organisation (`ChannelContacts.record/3`,
  source `person`, consent text `event_rsvp_v1`). The reminder before the
  event and a change to it then also go by SMS through the organisation's
  channel connection (`event_reminder`, `event_changed`), on top of the
  push notification. Attendees without that consent, or an organisation
  without a connection, in demo mode or over budget, get no SMS: the push
  notification still goes, so a refused SMS is never an error here.
  """

  alias Palee.Application.Channels.{ChannelContacts, SendThroughChannel}
  alias Palee.{Channels, Community}

  @consent_text "event_rsvp_v1"

  @doc "The consent text version shown next to the RSVP choice."
  def consent_text, do: @consent_text

  @doc """
  Records the attendee's number and SMS consent with the event's
  organisation when they asked for SMS. `:ok` when nothing was asked.
  """
  def record_consent(event, user_id, params) do
    if truthy?(params[:sms_consent]) do
      ChannelContacts.record(tenant(event), %{
        user_id: user_id,
        phone: params[:phone],
        locale: params[:locale],
        source: "person",
        text_version: @consent_text,
        consents: [%{channel: "sms", purpose: "service", granted: true}]
      })
      |> case do
        {:ok, _contact} -> :ok
        error -> error
      end
    else
      :ok
    end
  end

  @doc "The reminder before the event, to going attendees."
  def reminder(event, attendees, event_when),
    do: each(event, attendees, "event_reminder", event_when, "reminder:#{stamp(event.starts_at)}")

  @doc "A change to the event, to going attendees."
  def changed(event, attendees, event_when),
    do: each(event, attendees, "event_changed", event_when, "changed:#{stamp(event.updated_at)}")

  @doc """
  ADR-385: per organisation, whether «Θα έρθω» may ask for SMS: it has a
  connection with SMS switched on and is not in demo mode. Each event also
  needs its own switch on (`sms_enabled`).
  """
  def offered_by_org(organization_ids) do
    Map.new(Enum.uniq(organization_ids), fn organization_id ->
      context = %{organization_id: organization_id}
      {organization_id, sends_sms?(context)}
    end)
  end

  @doc """
  ADR-385: the organiser's view of one event: its switch, whether the
  organiser sends SMS, how many going people agreed to them («12 από 40 θα
  πάρουν SMS»), what this event's SMS cost so far and the price of one.
  """
  def summary(event) do
    context = tenant(event)
    going = Community.list_attendees(context, [event.id], ["going"])
    connection = Channels.connection(context)

    %{
      enabled: event.sms_enabled != false,
      connected: sends_sms?(context),
      going: length(going),
      recipients:
        Enum.count(going, &Channels.consented?(context, %{user_id: &1.user_id}, "sms", "service")),
      spent_cents: Channels.spent_on(context, "event:#{event.id}"),
      per_message_cents: Channels.unit_price(context, "sms", "service"),
      currency: (connection && connection.currency) || "EUR"
    }
  end

  defp sends_sms?(context) do
    case Channels.connection(context) do
      %{channels: channels, status: "active"} when is_list(channels) ->
        "sms" in channels and not SendThroughChannel.env(context, DateTime.utc_now()).demo

      _none ->
        false
    end
  end

  # ADR-385: the organiser switched SMS off for this event: push only.
  defp each(%{sms_enabled: false}, _attendees, _key, _event_when, _step), do: :ok

  defp each(event, attendees, key, event_when, step) do
    Enum.each(attendees, fn attendee ->
      # A person without consent or a box without a connection gets none.
      _result =
        SendThroughChannel.call(tenant(event), %{
          user_id: attendee.user_id,
          template_key: key,
          variables: %{"event" => event.title, "when" => event_when},
          channels: ["sms"],
          idempotency_key: "event:#{event.id}:#{step}:#{attendee.user_id}",
          source: "system",
          source_ref: "event:#{event.id}"
        })
    end)
  end

  defp tenant(event), do: %{organization_id: event.organization_id}

  defp truthy?(value), do: value in [true, "true"]

  defp stamp(nil), do: "none"
  defp stamp(%DateTime{} = at), do: at |> DateTime.to_unix(:microsecond) |> Integer.to_string()
end
