defmodule Palee.Ranks.Domain.LadderPolicy do
  @moduledoc """
  What a ladder of belts or levels may hold (ADR-377, CP-E2).

  * **Discipline**: one of the workout types of ADR-275, so ranks sit in
    the same families as WODs, stats and badges (a «Ζώνες BJJ» ladder is
    `bjj_grappling` in `combat`; «Ενόργανη γυναικών: επίπεδα» is
    `artistic_gymnastics` in `gymnastics`).
  * **Style**: `belt` (a colour, optional stripes) or `level` (a number or
    a name such as «Επίπεδο 3»).
  * **Ranks**: 1–30, in order; a name, a colour from the belt palette, up
    to 10 stripes, an optional scale level the rank suggests (ADR-128:
    a «Level 4» gymnast is offered the box's `rx` by default) and the
    requirements for reaching it: classes attended since the previous
    rank, days since it, and skills the coach ticks (up to 20).
  * **Templates** start a ladder in one tap (the calm default); every
    name stays editable. The catalogue (ADR-400) is `LadderTemplates`.
  """

  alias Palee.Ranks.Domain.LadderTemplates

  @styles ~w(belt level)
  @colors ~w(white grey yellow orange green blue purple brown red black pink)
  @max_ranks 30
  @max_skills 20

  def styles, do: @styles
  def colors, do: @colors
  def disciplines, do: Palee.Workouts.Domain.WorkoutType.keys()

  @doc "The family of a discipline (ADR-275)."
  def family(discipline), do: Palee.Workouts.Domain.WorkoutType.family(discipline)

  @doc """
  `{:ok, ranks}` (each `%{id?, position, name, color, max_stripes,
  requirements, scale_level_slug}`) or `{:error, {:invalid_ranks, message}}`.
  `scale_levels` are the box's slugs.
  """
  def cast_ranks(ranks, scale_levels) when is_list(ranks) do
    cond do
      ranks == [] or length(ranks) > @max_ranks ->
        {:error, {:invalid_ranks, "a ladder has 1 to #{@max_ranks} ranks"}}

      true ->
        ranks
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, []}, fn {rank, position}, {:ok, acc} ->
          case cast_rank(rank, position, scale_levels) do
            {:ok, cast} -> {:cont, {:ok, [cast | acc]}}
            {:error, message} -> {:halt, {:error, {:invalid_ranks, message}}}
          end
        end)
        |> case do
          {:ok, cast} -> unique_names(Enum.reverse(cast))
          error -> error
        end
    end
  end

  def cast_ranks(_ranks, _scale_levels),
    do: {:error, {:invalid_ranks, "send the ranks as a list"}}

  defp unique_names(ranks) do
    names = Enum.map(ranks, &String.downcase(&1.name))

    if length(names) == length(Enum.uniq(names)),
      do: {:ok, ranks},
      else: {:error, {:invalid_ranks, "each rank needs its own name"}}
  end

  defp cast_rank(rank, position, scale_levels) when is_map(rank) do
    name = rank |> get(:name) |> trim()
    color = get(rank, :color)
    stripes = get(rank, :max_stripes) || 0
    slug = get(rank, :scale_level_slug)

    with :ok <-
           check(
             is_binary(name) and name != "" and String.length(name) <= 60,
             "name each rank (up to 60 characters)"
           ),
         :ok <- check(is_nil(color) or color in @colors, "choose a colour from the palette"),
         :ok <- check(is_integer(stripes) and stripes in 0..10, "stripes are 0 to 10"),
         :ok <-
           check(is_nil(slug) or slug in scale_levels, "choose one of the box's scale levels"),
         {:ok, requirements} <- cast_requirements(get(rank, :requirements)),
         :ok <- check(id_ok?(get(rank, :id)), "a rank id is not valid") do
      {:ok,
       %{
         id: get(rank, :id),
         position: position,
         name: name,
         color: color,
         max_stripes: stripes,
         requirements: requirements,
         scale_level_slug: slug
       }}
    end
  end

  defp cast_rank(_rank, _position, _scale_levels), do: {:error, "each rank is an object"}

  @doc "Requirements: `min_classes` 0–2000, `min_days` 0–3650, `skills` up to 20 short lines."
  def cast_requirements(nil), do: {:ok, %{}}

  def cast_requirements(requirements) when is_map(requirements) do
    classes = get(requirements, :min_classes)
    days = get(requirements, :min_days)
    skills = get(requirements, :skills) || []

    with :ok <-
           check(
             is_nil(classes) or (is_integer(classes) and classes in 0..2000),
             "classes are 0 to 2000"
           ),
         :ok <-
           check(is_nil(days) or (is_integer(days) and days in 0..3650), "days are 0 to 3650"),
         :ok <-
           check(
             is_list(skills) and length(skills) <= @max_skills and
               Enum.all?(
                 skills,
                 &(is_binary(&1) and String.trim(&1) != "" and String.length(&1) <= 120)
               ),
             "up to #{@max_skills} skills of up to 120 characters"
           ) do
      {:ok,
       %{
         "min_classes" => classes,
         "min_days" => days,
         "skills" => Enum.map(skills, &String.trim/1)
       }
       |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
       |> Map.new()}
    end
  end

  def cast_requirements(_requirements), do: {:error, "requirements are an object"}

  @doc """
  Ready-made ladders («Πρότυπα», ADR-400): key, name, discipline, style,
  source (`federation` or `palee`), a short note on the system, and ranks.
  Texts are untranslated message ids; see `localize_template/2`.
  """
  def templates, do: LadderTemplates.all()

  @doc "The template with this key, or nil."
  def template(key), do: Enum.find(templates(), &(&1.key == key))

  @doc """
  A template in one language: `translate.(message_id, bindings)` gives the
  text (gettext's `rank_templates` domain; a `{context, message_id}` id
  carries a msgctxt). Numbered names (`{pattern, n}`) are translated with
  their number, exam names (`{:exam, name}`) in the "exam" context; the
  family of the discipline is added.
  """
  def localize_template(template, translate) when is_function(translate, 2) do
    %{
      template
      | name: translate.(template.name, %{}),
        ranks: Enum.map(template.ranks, &localize_rank(&1, translate))
    }
    |> localize_system(translate)
    |> Map.put(:family, family(template.discipline))
  end

  defp localize_system(%{system: system} = template, translate) when is_binary(system),
    do: %{template | system: translate.(system, %{})}

  defp localize_system(template, _translate), do: template

  defp localize_rank(rank, translate) do
    requirements =
      case rank.requirements do
        %{skills: skills} = requirements ->
          %{requirements | skills: Enum.map(skills, &translate.(&1, %{}))}

        requirements ->
          requirements
      end

    %{rank | name: rank_name(rank.name, translate), requirements: requirements}
  end

  defp rank_name({:exam, name}, translate), do: translate.({"exam", name}, %{})
  defp rank_name({pattern, number}, translate), do: translate.(pattern, %{n: number})
  defp rank_name(name, translate), do: translate.(name, %{})

  defp id_ok?(nil), do: true
  defp id_ok?(id), do: match?({:ok, _uuid}, Ecto.UUID.cast(id))

  defp check(true, _message), do: :ok
  defp check(false, message), do: {:error, message}

  defp trim(text) when is_binary(text), do: String.trim(text)
  defp trim(other), do: other

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
