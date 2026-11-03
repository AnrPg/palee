defmodule Palee.Email.Templates.ReviewReportsSummary do
  @moduledoc """
  `:review_reports_summary` (ADR-397): the Palee team's daily summary of
  reported box reviews waiting for a decision, with a link to the platform
  console «Αναφορές κριτικών». Sent only while reports are open.

  Assigns: `reviews`, `reports`, `oldest` (DateTime or nil), `url`.
  Strings: the `review_reports` gettext domain.

  Category `:account`: Palee's own mail to its team, never a business's.
  """

  use Palee.Email.Template, category: :account

  @domain "review_reports"

  # One a day.
  @impl true
  def throttle, do: %{max_per_day: 1, min_interval_seconds: 0}

  @impl true
  def subject(%{reviews: reviews}, locale),
    do: s(locale, "Review reports waiting: %{count}", %{count: reviews})

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(
      locale,
      [body(assigns, locale), Layout.text_button(s(locale, "Open the queue"), url)],
      reason: reason(locale)
    )
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(subject(assigns, locale)),
        Layout.paragraph(body(assigns, locale)),
        Layout.button(s(locale, "Open the queue"), url),
        Layout.fallback_link(locale, url)
      ],
      reason: reason(locale),
      preheader: body(assigns, locale)
    )
  end

  defp body(%{reviews: reviews, reports: reports} = assigns, locale),
    do:
      s(
        locale,
        "%{reviews} reviews with %{reports} reports wait for a decision, the oldest since %{date}. Until you decide, they stay up.",
        %{reviews: reviews, reports: reports, date: date(Map.get(assigns, :oldest))}
      )

  defp date(%DateTime{} = at), do: at |> DateTime.to_date() |> Date.to_iso8601()
  defp date(_none), do: "-"

  defp reason(locale),
    do: s(locale, "You get this email because you moderate box reviews for Palee.")

  defp s(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
