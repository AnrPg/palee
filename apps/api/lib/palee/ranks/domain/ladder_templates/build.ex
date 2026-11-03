defmodule Palee.Ranks.Domain.LadderTemplates.Build do
  @moduledoc """
  The shape of a template ladder (ADR-400). Texts are English message ids of
  the `rank_templates` gettext domain; a numbered name is `{pattern, n}`
  («Level %{n}», «Kyu %{n}»), translated with its number.
  """

  @doc "A template: `source` is `:federation` (a federation's or school's system) or `:palee` (Palee's own levels)."
  def template(key, name, discipline, style, source, system, ranks)
      when source in [:federation, :palee] do
    %{
      key: key,
      name: name,
      discipline: discipline,
      style: style,
      source: Atom.to_string(source),
      system: system,
      ranks: ranks
    }
  end

  @doc "A rank: `requirements` takes `days:` and `classes:`; skills are what is tested to reach it."
  def rank(name, color, stripes, requirements, skills) do
    %{
      name: name,
      color: color,
      max_stripes: stripes,
      requirements:
        %{
          min_days: Keyword.get(requirements, :days),
          min_classes: Keyword.get(requirements, :classes),
          skills: skills
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
        |> Map.new()
    }
  end
end
