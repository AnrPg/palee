defmodule Palee.Email.Templates.StatusUpdate do
  @moduledoc """
  `:status_update` (ADR-364): an incident or planned maintenance on the
  Palee status page, or a new step in one, to confirmed subscribers.

  Assigns: `kind` (`incident` | `maintenance`), `title`, `status`, `body`
  (the team's note), `scheduled_for`/`scheduled_until` (maintenance, UTC),
  `url` (the status page), `unsubscribe_url`. Strings live in the `status`
  gettext domain.
  """

  use Palee.Email.Template, category: :transactional

  @domain "status"

  @impl true
  def throttle, do: %{min_interval_seconds: 0, max_per_day: 30}

  @impl true
  def subject(%{title: title} = assigns, locale),
    do: "[#{status_label(assigns.status, locale)}] #{title}"

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(
      locale,
      [
        assigns.title,
        "#{status_label(assigns.status, locale)}: #{assigns.body}"
      ] ++
        window_text(assigns, locale) ++
        [
          Layout.text_button(tr(locale, "Open the status page"), url),
          Layout.text_button(tr(locale, "Stop these emails"), assigns.unsubscribe_url)
        ],
      reason: reason(locale)
    )
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(assigns.title),
        Layout.details(
          [{tr(locale, "Status"), status_label(assigns.status, locale)}] ++
            window_rows(assigns, locale)
        ),
        Layout.paragraph(assigns.body),
        Layout.button(tr(locale, "Open the status page"), url),
        Layout.fallback_link(locale, url),
        Layout.paragraph(tr(locale, "Stop these emails") <> ": " <> assigns.unsubscribe_url)
      ],
      preheader: assigns.body,
      reason: reason(locale)
    )
  end

  defp reason(locale),
    do: tr(locale, "You get these emails because you asked for them on the status page.")

  defp window_rows(%{kind: "maintenance", scheduled_for: from, scheduled_until: until}, locale)
       when not is_nil(from) and not is_nil(until),
       do: [{tr(locale, "When"), "#{utc(from)} – #{utc(until)}"}]

  defp window_rows(_assigns, _locale), do: []

  defp window_text(assigns, locale),
    do: Enum.map(window_rows(assigns, locale), fn {label, value} -> "#{label}: #{value}" end)

  defp utc(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")

  defp utc(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> utc(datetime)
      _error -> value
    end
  end

  defp status_label("investigating", locale), do: tr(locale, "Investigating")
  defp status_label("identified", locale), do: tr(locale, "Identified")
  defp status_label("monitoring", locale), do: tr(locale, "Monitoring")
  defp status_label("resolved", locale), do: tr(locale, "Resolved")
  defp status_label("scheduled", locale), do: tr(locale, "Scheduled maintenance")
  defp status_label("in_progress", locale), do: tr(locale, "Maintenance in progress")
  defp status_label("completed", locale), do: tr(locale, "Maintenance completed")
  defp status_label(other, _locale), do: other

  defp tr(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
