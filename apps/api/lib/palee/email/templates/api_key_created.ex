defmodule Palee.Email.Templates.ApiKeyCreated do
  @moduledoc """
  `:api_key_created` (ADR-378, 2026-11-03): a new API key was made for the
  box. To each person who manages the box's settings, so a key made without
  them is seen and can be revoked. It names the key, its masked prefix, its
  scopes, who made it and when; it never carries the key.

  Assigns: `url` (Settings › Συνδέσεις › Κλειδιά API), `box`, `name`,
  `masked`, `scopes`, `maker`, `at` (the box's local time). Strings live in
  the `integrations` gettext domain.
  """

  use Palee.Email.Template, category: :security

  @domain "integrations"

  @impl true
  def throttle, do: %{min_interval_seconds: 0, max_per_day: 20}

  @impl true
  def subject(assigns, locale),
    do: tr(locale, "New API key for %{box}", %{box: Map.get(assigns, :box, "")})

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(locale, [
      Layout.t(locale, "Hello,"),
      what(assigns, locale),
      Layout.text_details(rows(assigns, locale)),
      advice(locale),
      Layout.text_button(tr(locale, "Open API keys"), url)
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
        Layout.details(rows(assigns, locale)),
        Layout.paragraph(advice(locale)),
        Layout.button(tr(locale, "Open API keys"), url),
        Layout.fallback_link(locale, url)
      ],
      preheader: what(assigns, locale)
    )
  end

  defp what(assigns, locale),
    do:
      tr(
        locale,
        "A new API key can now read or change %{box}'s data through Palee's public API.",
        %{box: Map.get(assigns, :box, "")}
      )

  defp rows(assigns, locale),
    do: [
      {tr(locale, "Key"), "#{Map.get(assigns, :name, "")} (#{Map.get(assigns, :masked, "")})"},
      {tr(locale, "Access"), Map.get(assigns, :scopes, "")},
      {tr(locale, "Made by"), Map.get(assigns, :maker, "")},
      {tr(locale, "When"), Map.get(assigns, :at, "")}
    ]

  defp advice(locale),
    do: tr(locale, "If nobody at the box made it, revoke it now from Settings › Connections.")

  defp tr(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
