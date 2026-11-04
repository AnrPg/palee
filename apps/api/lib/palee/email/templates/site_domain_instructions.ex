defmodule Palee.Email.Templates.SiteDomainInstructions do
  @moduledoc """
  `:site_domain_instructions` (ADR-388): «Στείλε τις οδηγίες». The box's
  owner sends the DNS records of their website's own domain to whoever runs
  the domain (often the person who built the old site), with a link to a
  page that shows whether the records are found yet.

  Assigns: `box_name`, `host`, `records` (`[%{type, name, value}]`),
  `status_url`. Rendered in the box's language. Strings: the `box_site`
  gettext domain.

  Category `:transactional`: a demo business sends nothing (ADR-184).
  """

  use Palee.Email.Template, category: :transactional

  @domain "box_site"

  # A handful a day to one address: enough to resend, too few to annoy.
  @impl true
  def throttle, do: %{max_per_day: 5, min_interval_seconds: 0}

  @impl true
  def subject(%{host: host}, locale),
    do: s(locale, "DNS records for %{host}", %{host: host})

  @impl true
  def text(%{status_url: url} = assigns, locale) do
    Layout.text(
      locale,
      [intro(assigns, locale), steps(locale), records_text(assigns.records), after_text(locale)] ++
        [Layout.text_button(s(locale, "See if the records are found"), url)],
      reason: reason(assigns, locale)
    )
  end

  @impl true
  def html(%{status_url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(subject(assigns, locale)),
        Layout.paragraph(intro(assigns, locale)),
        Layout.paragraph(steps(locale))
      ] ++
        Enum.map(assigns.records, &Layout.paragraph(record_line(&1))) ++
        [
          Layout.paragraph(after_text(locale)),
          Layout.button(s(locale, "See if the records are found"), url),
          Layout.fallback_link(locale, url)
        ],
      reason: reason(assigns, locale),
      preheader: intro(assigns, locale)
    )
  end

  defp intro(%{box_name: box, host: host}, locale),
    do:
      s(
        locale,
        "%{box} wants its website to open at %{host}. Whoever manages the domain can do it in a few minutes.",
        %{box: box, host: host}
      )

  defp steps(locale),
    do: s(locale, "Add these records at the domain's provider (DNS settings):")

  defp after_text(locale),
    do:
      s(
        locale,
        "We check every few minutes. When the records are found, the site gets its certificate (https) by itself."
      )

  defp reason(%{box_name: box}, locale),
    do:
      s(locale, "You get this email because %{box} sent you its domain instructions.", %{box: box})

  defp records_text(records), do: Enum.map_join(records, "\n", &record_line/1)

  # An apex cannot have a CNAME; providers call the same thing differently.
  defp record_line(%{type: "ALIAS", name: name, value: value}),
    do: "CNAME flattening / ALIAS / ANAME  #{name}  →  #{value}"

  defp record_line(%{type: type, name: name, value: value}), do: "#{type}  #{name}  →  #{value}"

  defp s(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
