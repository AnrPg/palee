defmodule Palee.Email.Templates.ActivityLogDigest do
  @moduledoc """
  `:activity_log_digest` (ADR-760, ANR 12B): to each owner of a box, the
  morning after a day with sensitive actions: how many of each kind, with
  the way to «Αρχείο ενεργειών» filtered to that day's sensitive rows.

  Assigns: `box`, `date` (the box's day), `total`, `lines` (one per kind,
  already in the owner's language: `Application.ActivityLogDigest.lines/2`),
  `url`. Strings: the `activity_log` gettext domain.
  """

  use Palee.Email.Template, category: :account

  @domain "activity_log"

  # One a day per box; an owner of several boxes gets one for each.
  @impl true
  def throttle, do: %{min_interval_seconds: 0, max_per_day: 20}

  @impl true
  def subject(assigns, locale),
    do:
      Palee.Localization.translate_plural(
        locale,
        "%{box}: %{count} sensitive action yesterday",
        "%{box}: %{count} sensitive actions yesterday",
        Map.get(assigns, :total, 0),
        %{box: Map.get(assigns, :box, "")},
        @domain
      )

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(
      locale,
      [
        intro(assigns, locale),
        Enum.join(Map.get(assigns, :lines, []), "\n"),
        Layout.text_button(tr(locale, "Open the activity log"), url)
      ],
      reason: reason(assigns, locale)
    )
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(subject(assigns, locale)),
        Layout.paragraph(intro(assigns, locale)),
        assigns |> Map.get(:lines, []) |> Enum.map_join("", &Layout.paragraph/1),
        Layout.button(tr(locale, "Open the activity log"), url),
        Layout.fallback_link(locale, url)
      ],
      reason: reason(assigns, locale),
      preheader: intro(assigns, locale)
    )
  end

  defp intro(assigns, locale),
    do:
      tr(
        locale,
        "What your staff did at %{box} yesterday, %{date}, that the activity log marks as sensitive:",
        %{box: Map.get(assigns, :box, ""), date: date(Map.get(assigns, :date))}
      )

  defp reason(assigns, locale),
    do:
      tr(locale, "You get this email because you are an owner of %{box} on Palee.", %{
        box: Map.get(assigns, :box, "")
      })

  defp date(%Date{} = day), do: Calendar.strftime(day, "%d/%m/%Y")
  defp date(value) when is_binary(value), do: value
  defp date(_value), do: ""

  defp tr(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
