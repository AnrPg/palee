defmodule Palee.Email.Templates.WorkoutKindsDigest do
  @moduledoc """
  `:workout_kinds_digest` (ADR-690): the Palee team's daily email of the
  workout type names boxes added (and the disciplines they suggested on their
  public page) since the last one, with a link to the console «Προτάσεις
  τύπων». Sent only on days with news.

  Assigns: `names` (`[%{label, boxes, suggestions}]`), `url`.
  Strings: the `workout_kinds` gettext domain.

  Category `:account`: Palee's own mail to its team, never a business's.
  """

  use Palee.Email.Template, category: :account

  @domain "workout_kinds"

  # One a day.
  @impl true
  def throttle, do: %{max_per_day: 1, min_interval_seconds: 0}

  @impl true
  def subject(%{names: names}, locale),
    do: s(locale, "New workout types to review: %{count}", %{count: length(names)})

  @impl true
  def text(%{url: url} = assigns, locale) do
    Layout.text(
      locale,
      [
        intro(locale),
        lines(assigns, locale),
        Layout.text_button(s(locale, "Open the queue"), url)
      ],
      reason: reason(locale)
    )
  end

  @impl true
  def html(%{url: url} = assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(subject(assigns, locale)),
        Layout.paragraph(intro(locale)),
        assigns |> line_list(locale) |> Enum.map_join("", &Layout.paragraph/1),
        Layout.button(s(locale, "Open the queue"), url),
        Layout.fallback_link(locale, url)
      ],
      reason: reason(locale),
      preheader: intro(locale)
    )
  end

  defp intro(locale),
    do:
      s(
        locale,
        "Boxes added these workout types. Each one is in its box's list already; decide whether it joins the Palee list for everyone."
      )

  defp lines(assigns, locale), do: assigns |> line_list(locale) |> Enum.join("\n")

  defp line_list(%{names: names}, locale) do
    Enum.map(names, fn name ->
      s(locale, "«%{label}»: %{boxes} boxes, %{suggestions} public page suggestions", %{
        label: name.label,
        boxes: name.boxes,
        suggestions: name.suggestions
      })
    end)
  end

  defp reason(locale),
    do: s(locale, "You get this email because you review workout types for Palee.")

  defp s(locale, message, bindings \\ %{}),
    do: Palee.Localization.translate(locale, message, bindings, @domain)
end
