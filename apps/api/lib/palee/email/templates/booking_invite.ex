defmodule Palee.Email.Templates.BookingInvite do
  @moduledoc """
  `:booking_invite` (ADR-392): «Email κράτησης με ημερολόγιο». One email when
  a seat in a class is confirmed, when its class moves, and when the seat or
  the class is cancelled, with the class's calendar invite attached
  (`text/calendar`, `METHOD:REQUEST` or `METHOD:CANCEL`, the same UID as the
  person's calendar feed and the «Προσθήκη στο ημερολόγιο» download).

  Transactional mail from the box (ADR-184 demo gate, ADR-212 one-click
  unsubscribe, ADR-368 the box's own sender). The person turns it off in
  Ρυθμίσεις › Ειδοποιήσεις; the caller checks that switch.

  Assigns: `kind` (`:booked`, `:changed` or `:cancelled`), `business` (the
  box's name), `class_name`, `starts_at` (UTC) and `time_zone` (the gym's,
  ADR-176/179: the email says the day and time on the gym's clock, the
  weekday in the reader's language), `location` (or nil), `url` (the class
  in the app). Strings: the `emails` gettext domain.
  """

  use Palee.Email.Template, category: :transactional, origin: :box

  # A booking, a move and a cancellation of the same class can come close
  # together; a person booking many classes gets one each, within reason.
  @impl true
  def throttle, do: %{max_per_day: 20, min_interval_seconds: 0}

  @impl true
  def subject(%{kind: :cancelled} = assigns, locale),
    do: t(locale, "Cancelled: %{class}, %{when}", bindings(assigns, locale))

  def subject(%{kind: :changed} = assigns, locale),
    do: t(locale, "Class changed: %{class}, %{when}", bindings(assigns, locale))

  def subject(assigns, locale),
    do: t(locale, "Booked: %{class}, %{when}", bindings(assigns, locale))

  @impl true
  def text(assigns, locale) do
    Layout.text(
      locale,
      [
        intro(assigns, locale),
        Layout.text_details(details(assigns, locale)),
        attachment_line(assigns, locale),
        Layout.text_button(t(locale, "Open in the app"), assigns.url),
        settings_line(locale)
      ],
      reason: Layout.reason(locale, {:business, assigns.business})
    )
  end

  @impl true
  def html(assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(subject(assigns, locale)),
        Layout.paragraph(intro(assigns, locale)),
        Layout.details(details(assigns, locale)),
        Layout.paragraph(attachment_line(assigns, locale)),
        Layout.button(t(locale, "Open in the app"), assigns.url),
        Layout.note(settings_line(locale))
      ],
      reason: Layout.reason(locale, {:business, assigns.business}),
      preheader: intro(assigns, locale)
    )
  end

  defp bindings(assigns, locale),
    do: %{class: assigns.class_name, when: when_text(assigns, locale)}

  @weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  @doc false
  # «Monday 24/11 19:00» on the gym's clock (ADR-179), the weekday translated.
  def when_text(%{starts_at: %DateTime{} = at} = assigns, locale) do
    zone = Map.get(assigns, :time_zone)
    local = Palee.TimeZones.ZonedTime.local(at, zone)
    weekday = Enum.at(@weekdays, Date.day_of_week(local) - 1)

    t(locale, "%{weekday} %{date_time}", %{
      weekday: weekday_name(locale, weekday),
      date_time: Palee.TimeZones.ZonedTime.format(at, zone)
    })
  end

  defp weekday_name(locale, "Monday"), do: t(locale, "Monday")
  defp weekday_name(locale, "Tuesday"), do: t(locale, "Tuesday")
  defp weekday_name(locale, "Wednesday"), do: t(locale, "Wednesday")
  defp weekday_name(locale, "Thursday"), do: t(locale, "Thursday")
  defp weekday_name(locale, "Friday"), do: t(locale, "Friday")
  defp weekday_name(locale, "Saturday"), do: t(locale, "Saturday")
  defp weekday_name(locale, "Sunday"), do: t(locale, "Sunday")

  defp intro(%{kind: :cancelled} = assigns, locale),
    do:
      t(locale, "Your place in %{class} at «%{business}» is cancelled.", %{
        class: assigns.class_name,
        business: assigns.business
      })

  defp intro(%{kind: :changed} = assigns, locale),
    do:
      t(locale, "%{class} at «%{business}» changed. Your place is kept.", %{
        class: assigns.class_name,
        business: assigns.business
      })

  defp intro(assigns, locale),
    do:
      t(locale, "Your place in %{class} at «%{business}» is booked.", %{
        class: assigns.class_name,
        business: assigns.business
      })

  defp details(assigns, locale) do
    [
      {t(locale, "Class"), assigns.class_name},
      {t(locale, "When"), when_text(assigns, locale)}
    ] ++
      case Map.get(assigns, :location) do
        location when is_binary(location) and location != "" -> [{t(locale, "Where"), location}]
        _none -> []
      end
  end

  defp attachment_line(%{kind: :cancelled}, locale),
    do: t(locale, "The attached invite removes the class from your calendar.")

  defp attachment_line(_assigns, locale),
    do: t(locale, "The attached invite adds the class to your calendar, or updates it.")

  defp settings_line(locale),
    do: t(locale, "You can turn these emails off in Settings › Notifications.")
end
