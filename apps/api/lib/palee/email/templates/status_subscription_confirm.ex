defmodule Palee.Email.Templates.StatusSubscriptionConfirm do
  @moduledoc """
  `:status_subscription_confirm` (ADR-364): confirm the sign-up for status
  emails (double opt-in). Assigns: `url` (the status page with the one-time
  token). Strings live in the `status` gettext domain.
  """

  use Palee.Email.Template, category: :account

  @domain "status"

  @impl true
  def subject(_assigns, locale), do: tr(locale, "Confirm your Palee status emails")

  @impl true
  def text(%{url: url}, locale) do
    Layout.text(locale, [
      Layout.t(locale, "Hello,"),
      what(locale),
      Layout.text_button(tr(locale, "Confirm"), url),
      not_you(locale)
    ])
  end

  @impl true
  def html(%{url: url}, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(tr(locale, "Confirm your Palee status emails")),
        Layout.paragraph(Layout.t(locale, "Hello,")),
        Layout.paragraph(what(locale)),
        Layout.button(tr(locale, "Confirm"), url),
        Layout.fallback_link(locale, url),
        Layout.note(not_you(locale))
      ],
      preheader: what(locale)
    )
  end

  defp what(locale),
    do:
      tr(
        locale,
        "Someone asked to get an email when Palee has an incident or planned maintenance. Confirm and we will write to this address only then."
      )

  defp not_you(locale),
    do: tr(locale, "If it wasn't you, ignore this email: nothing will be sent.")

  defp tr(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
