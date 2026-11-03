defmodule Palee.Email.Templates.BoxDataExportReady do
  @moduledoc """
  `:box_data_export_ready` (ADR-367): the copy of the box's data the owner
  asked for is ready. One email, sent to the owner who asked. It carries no
  download link, only the way to Settings › Business, where the signed-in
  owner gets short-lived ones.

  Assigns: `url` (the settings section), `box` (the box's name), `keep_days`.
  Strings live in the `box_data` gettext domain.
  """

  use Palee.Email.Template, category: :account

  @domain "box_data"

  @impl true
  def subject(_assigns, locale), do: tr(locale, "The box's data is ready to download")

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(locale, [
      Layout.t(locale, "Hello,"),
      what(assigns, locale),
      where(assigns, locale),
      Layout.text_button(tr(locale, "Open Settings"), url)
    ])
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(tr(locale, "The box's data is ready to download")),
        Layout.paragraph(Layout.t(locale, "Hello,")),
        Layout.paragraph(what(assigns, locale)),
        Layout.paragraph(where(assigns, locale)),
        Layout.button(tr(locale, "Open Settings"), url),
        Layout.fallback_link(locale, url)
      ],
      preheader: what(assigns, locale)
    )
  end

  defp what(assigns, locale),
    do:
      tr(
        locale,
        "The copy of %{box}'s data you asked for is ready: members, packages, payments, classes, workouts, documents, photos and PDFs.",
        %{box: Map.get(assigns, :box, "")}
      )

  defp where(%{keep_days: days}, locale),
    do:
      tr(
        locale,
        "Download it from Settings › Business while you are signed in. It is kept for %{days} days.",
        %{days: days}
      )

  defp tr(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
