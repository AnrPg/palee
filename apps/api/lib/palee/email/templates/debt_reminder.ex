defmodule Palee.Email.Templates.DebtReminder do
  @moduledoc """
  `:debt_reminder` (ADR-396): the payment reminder of a person whose Palee
  profile was deleted while they still owed a box money. They have no app to
  see it in, so it goes to the email the box kept for the debt. Carries no
  link (there is no account to sign in to), only who to contact.

  Assigns: `box` (the box's name), `amount_cents`, `currency`.
  Strings live in the `debts` gettext domain.
  """

  use Palee.Email.Template, category: :transactional, origin: :box

  @domain "debts"

  @impl true
  def subject(assigns, locale),
    do: tr(locale, "You still owe %{box} %{amount}", bindings(assigns, locale))

  @impl true
  def text(assigns, locale) do
    Layout.text(locale, [
      Layout.t(locale, "Hello,"),
      what(assigns, locale),
      how(assigns, locale)
    ])
  end

  @impl true
  def html(assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(subject(assigns, locale)),
        Layout.paragraph(Layout.t(locale, "Hello,")),
        Layout.paragraph(what(assigns, locale)),
        Layout.paragraph(how(assigns, locale))
      ],
      preheader: what(assigns, locale)
    )
  end

  defp what(assigns, locale),
    do:
      tr(
        locale,
        "Your Palee account was deleted, but the %{amount} you owe %{box} is still unpaid.",
        bindings(assigns, locale)
      )

  defp how(assigns, locale),
    do:
      tr(
        locale,
        "Please contact %{box} to settle it. Once it is paid, %{box} deletes the name, email and phone number it kept for it.",
        bindings(assigns, locale)
      )

  defp bindings(assigns, locale),
    do: %{box: Map.get(assigns, :box, ""), amount: amount(assigns, locale)}

  @doc false
  def amount(%{amount_cents: cents} = assigns, locale) when is_integer(cents) do
    number = :erlang.float_to_binary(cents / 100, decimals: 2)
    number = if locale in ["en", "he", "ar"], do: number, else: String.replace(number, ".", ",")

    case Map.get(assigns, :currency, "EUR") do
      "EUR" -> number <> " €"
      currency -> number <> " " <> currency
    end
  end

  def amount(_assigns, _locale), do: ""

  defp tr(locale, message, bindings),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
