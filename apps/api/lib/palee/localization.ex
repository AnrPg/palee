defmodule Palee.Localization do
  @moduledoc false

  def translate(locale, message, bindings \\ %{}, domain \\ "notifications") do
    adapter().translate(locale, domain, message, bindings)
  end

  @doc """
  A text with a count, in the plural form `count` takes in `locale` (ADR-600:
  «+14 ακόμη παρόμοιες»). `%{count}` is bound to `count`.
  """
  def translate_plural(
        locale,
        singular,
        plural,
        count,
        bindings \\ %{},
        domain \\ "notifications"
      )
      when is_integer(count) do
    adapter().translate_plural(locale, domain, singular, plural, count, bindings)
  end

  defp adapter do
    Application.get_env(
      :palee,
      :localization_adapter,
      Palee.Infrastructure.Localization.GettextAdapter
    )
  end
end
