defmodule Palee.Infrastructure.Localization.GettextAdapter do
  @moduledoc false

  alias Palee.Infrastructure.Localization.GettextBackend

  def translate(locale, domain, message, bindings) do
    gettext_locale = if locale == "pt-PT", do: "pt_PT", else: locale || "en"

    Gettext.with_locale(GettextBackend, gettext_locale, fn ->
      lookup(domain, message, bindings)
    end)
  end

  # `{context, message_id}` looks the text up under its msgctxt.
  defp lookup(domain, {context, message}, bindings),
    do: Gettext.dpgettext(GettextBackend, domain, context, message, bindings)

  defp lookup(domain, message, bindings),
    do: Gettext.dgettext(GettextBackend, domain, message, bindings)
end
