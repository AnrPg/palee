defmodule Palee.Email.Templates.BoxAutomation do
  @moduledoc """
  `:box_automation` (ADR-346): a box's automatic message (welcome, trial
  follow-up, birthday...) sent by email. The subject and text are already
  written and filled in by the recipe, in the reader's language or the
  box's own words, so this template adds nothing but the layout and says
  which box sent it. Transactional mail, so it carries the one-click
  unsubscribe of ADR-212, which stops this kind for the address.

  Assigns: `subject`, `body` (plain text, paragraphs split by blank lines),
  `box_name`.
  """

  use Palee.Email.Template, category: :transactional

  # At most a few automatic messages a day to one address, whatever the box
  # switched on.
  @impl true
  def throttle, do: %{min_interval_seconds: 0, max_per_day: 3}

  @impl true
  def subject(assigns, _locale), do: assigns.subject

  @impl true
  def text(assigns, locale),
    do: Layout.text(locale, paragraphs(assigns.body), reason: reason(assigns, locale))

  @impl true
  def html(assigns, locale) do
    Layout.html(
      locale,
      [Layout.heading(assigns.subject) | Enum.map(paragraphs(assigns.body), &Layout.paragraph/1)],
      reason: reason(assigns, locale),
      preheader: assigns.body |> paragraphs() |> List.first()
    )
  end

  defp paragraphs(body),
    do: body |> to_string() |> String.split(~r/\n\s*\n/u, trim: true) |> Enum.map(&String.trim/1)

  defp reason(assigns, locale), do: Layout.reason(locale, {:business, assigns.box_name})
end
