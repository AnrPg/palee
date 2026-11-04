defmodule Palee.Ranks.Domain.LadderTemplates.Build do
  @moduledoc """
  The shape of a template ladder (ADR-400). Texts are English message ids of
  the `rank_templates` gettext domain; a numbered name is `{pattern, n}`
  («Level %{n}», «Kyu %{n}»), translated with its number; an exam's own name
  is `{:exam, name}` (msgctxt "exam"), so «Intermediate» as an RAD or ISTD
  exam keeps its English name with a gloss and is never the generic level.
  """

  @doc """
  A template: `source` is `:federation` (a federation's or school's system)
  or `:palee` (Palee's own levels). `ready` (what counts for «Πληροί τις
  προϋποθέσεις») follows what the system itself states: days or classes
  only where some rank has a minimum, skills where ranks list them; a
  ladder with none of these counts its skills.
  """
  def template(key, name, discipline, style, source, system, ranks)
      when source in [:federation, :palee] do
    %{
      ready: ready(ranks),
      key: key,
      name: name,
      discipline: discipline,
      style: style,
      source: Atom.to_string(source),
      system: system,
      ranks: ranks
    }
  end

  defp ready(ranks) do
    has = fn key -> Enum.any?(ranks, &Map.has_key?(&1.requirements, key)) end

    case Enum.filter([days: :min_days, classes: :min_classes, skills: :skills], fn {_c, key} ->
           has.(key)
         end) do
      [] -> ["skills"]
      found -> Enum.map(found, fn {criterion, _key} -> Atom.to_string(criterion) end)
    end
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
