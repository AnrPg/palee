defmodule Palee.Infrastructure.Localization.GettextAdapter do
  @moduledoc false

  alias Palee.Infrastructure.Localization.GettextBackend

  def translate(locale, domain, message, bindings) do
    Gettext.with_locale(GettextBackend, gettext_locale(locale), fn ->
      lookup(domain, message, bindings)
    end)
  end

  def translate_plural(locale, domain, singular, plural, count, bindings) do
    Gettext.with_locale(GettextBackend, gettext_locale(locale), fn ->
      Gettext.dngettext(GettextBackend, domain, singular, plural, count, bindings)
    end)
  end

  defp gettext_locale("pt-PT"), do: "pt_PT"
  defp gettext_locale(locale), do: locale || "en"

  # `{context, message_id}` looks the text up under its msgctxt.
  defp lookup(domain, {context, message}, bindings),
    do: Gettext.dpgettext(GettextBackend, domain, context, message, bindings)

  defp lookup(domain, message, bindings),
    do: Gettext.dgettext(GettextBackend, domain, message, bindings)
end
