defmodule Palee.Email.Templates.WebhookDisabled do
  @moduledoc """
  `:webhook_disabled` (ADR-379, 2026-11-03): Palee turned off one of the
  box's webhooks. To each person who manages the box's settings, with the
  way to the webhook's page, where «Ενεργό» turns it back on and «Ξανά»
  resends what failed.

  Assigns: `url` (the webhook's page), `box`, `host` (the receiver's host),
  `reason` (`too_many_failures`, `gone`, `blocked_address`). Strings live in
  the `integrations` gettext domain.
  """

  use Palee.Email.Template, category: :account

  @domain "integrations"

  @impl true
  def throttle, do: %{min_interval_seconds: 0, max_per_day: 20}

  @impl true
  def subject(assigns, locale),
    do: tr(locale, "A webhook of %{box} was turned off", %{box: Map.get(assigns, :box, "")})

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(locale, [
      Layout.t(locale, "Hello,"),
      what(assigns, locale),
      why(assigns, locale),
      next(locale),
      Layout.text_button(tr(locale, "Open the webhook"), url)
    ])
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(subject(assigns, locale)),
        Layout.paragraph(Layout.t(locale, "Hello,")),
        Layout.paragraph(what(assigns, locale)),
        Layout.paragraph(why(assigns, locale)),
        Layout.paragraph(next(locale)),
        Layout.button(tr(locale, "Open the webhook"), url),
        Layout.fallback_link(locale, url)
      ],
      preheader: what(assigns, locale)
    )
  end

  defp what(assigns, locale),
    do:
      tr(locale, "Palee stopped sending events to %{host}.", %{host: Map.get(assigns, :host, "")})

  defp why(%{reason: "gone"}, locale),
    do: tr(locale, "The receiver answered that the address no longer exists.")

  defp why(%{reason: "blocked_address"}, locale),
    do: tr(locale, "The address now points to a private network, which Palee does not call.")

  defp why(_assigns, locale),
    do: tr(locale, "Every delivery failed many times in a row, so Palee stopped trying.")

  defp next(locale),
    do:
      tr(
        locale,
        "Check the receiver, then turn the webhook back on from its page and resend what failed."
      )

  defp tr(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
