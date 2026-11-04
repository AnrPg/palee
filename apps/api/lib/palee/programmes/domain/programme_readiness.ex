defmodule Palee.Programmes.Domain.ProgrammeReadiness do
  @moduledoc """
  ADR-544: «Λείπουν N πράγματα», what a programme's draft still lacks
  before it is published, pure. A calm list the editor shows instead of an
  error on «Δημοσίευση»; each item names where to go.

    * `title`: no title (blocking);
    * `price`: no price (blocking: only a paid programme is sold);
    * `days`: no WOD on any day (blocking);
    * `empty_weeks`: weeks with no WOD (`weeks`, 1-based; advisory);
    * `summary`: no summary (advisory: it is shown first on the page).

  A cover photo is never required (the page falls back to the theme
  colour). Blocking items are the ones `ProgrammePolicy.publishable/2`
  refuses; the others never stop a publication.
  """

  @doc "`[%{key, blocking, weeks}]` in the order the editor lists them."
  def check(programme) do
    days = programme.draft_days || []
    weeks = programme.draft_weeks || 1

    [
      blank?(programme.title) && item("title", true),
      not (is_integer(programme.price_cents) and programme.price_cents > 0) &&
        item("price", true),
      days == [] && item("days", true),
      days != [] && empty_weeks(days, weeks),
      blank?(programme.summary) && item("summary", false)
    ]
    |> Enum.filter(&is_map/1)
  end

  defp empty_weeks(days, weeks) do
    used = days |> Enum.map(&(div(day(&1), 7) + 1)) |> MapSet.new()

    case Enum.reject(1..weeks, &MapSet.member?(used, &1)) do
      [] -> nil
      empty -> item("empty_weeks", false, empty)
    end
  end

  defp day(row), do: row["day"] || row[:day] || 0

  defp item(key, blocking, weeks \\ []), do: %{key: key, blocking: blocking, weeks: weeks}

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
