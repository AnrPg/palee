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
  @ready_criteria ~w(days classes skills)
  @colors ~w(white grey yellow orange green blue purple brown red black pink)
  @max_ranks 30
  @max_skills 20

  def styles, do: @styles

  @doc "What may count for «Πληροί τις προϋποθέσεις», per ladder (ADR-400 follow-up)."
  def ready_criteria, do: @ready_criteria

  @doc "The criteria a ladder counts: a non-empty subset, in a fixed order; nil keeps `default`."
  def cast_ready_criteria(nil, default), do: {:ok, default}

  def cast_ready_criteria(criteria, _default) when is_list(criteria) do
    if criteria != [] and Enum.all?(criteria, &(&1 in @ready_criteria)),
      do: {:ok, Enum.filter(@ready_criteria, &(&1 in criteria))},
      else: {:error, {:invalid_ranks, "choose at least one of days, classes and skills"}}
  end

  def cast_ready_criteria(_criteria, _default),
    do: {:error, {:invalid_ranks, "choose at least one of days, classes and skills"}}

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

  @doc """
  Requirements: `min_classes` 0–2000, `min_days` 0–3650, `skills` up to 20
  short lines and their stable ids `skill_ids` (same order; an entry may be
  nil for a new skill, see `assign_skill_ids/2`).
  """
  def cast_requirements(nil), do: {:ok, %{}}

  def cast_requirements(requirements) when is_map(requirements) do
    classes = get(requirements, :min_classes)
    days = get(requirements, :min_days)
    skills = get(requirements, :skills) || []
    ids = get(requirements, :skill_ids)

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
           ),
         {:ok, ids} <- cast_skill_ids(ids, length(skills)),
         {:ok, notes} <-
           cast_skill_extras(get(requirements, :skill_notes), length(skills), &note_ok?/1),
         {:ok, videos} <-
           cast_skill_extras(get(requirements, :skill_videos), length(skills), &video_ok?/1) do
      skills = Enum.map(skills, &String.trim/1)

      {:ok,
       %{
         "min_classes" => classes,
         "min_days" => days,
         "skills" => skills,
         "skill_ids" => if(skills == [], do: [], else: ids),
         "skill_notes" => notes,
         "skill_videos" => videos
       }
       |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
       |> Map.new()}
    end
  end

  def cast_requirements(_requirements), do: {:error, "requirements are an object"}

  # A coach's note (up to 500 characters) and a video link (https) per
  # skill, in the order of `skills`; left out when no skill has one.
  defp cast_skill_extras(nil, _count, _ok?), do: {:ok, nil}

  defp cast_skill_extras(values, count, ok?) when is_list(values) and length(values) == count do
    values = Enum.map(values, &blank_to_nil/1)

    cond do
      not Enum.all?(values, &(is_nil(&1) or ok?.(&1))) ->
        {:error, "a skill's note is up to 500 characters and its video an https link"}

      Enum.all?(values, &is_nil/1) ->
        {:ok, nil}

      true ->
        {:ok, values}
    end
  end

  defp cast_skill_extras(_values, _count, _ok?),
    do: {:error, "send one note and one video per skill"}

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp note_ok?(note), do: is_binary(note) and String.length(note) <= 500

  defp video_ok?(url) when is_binary(url) and byte_size(url) <= 500 do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      _other -> false
    end
  end

  defp video_ok?(_url), do: false

  defp cast_skill_ids(nil, count), do: {:ok, List.duplicate(nil, count)}

  defp cast_skill_ids(ids, count) when is_list(ids) and length(ids) == count do
    if Enum.all?(ids, &(&1 in [nil, ""] or id_ok?(&1))),
      do: {:ok, Enum.map(ids, &if(&1 in [nil, ""], do: nil, else: String.downcase(&1)))},
      else: {:error, "a skill id is not valid"}
  end

  defp cast_skill_ids(_ids, _count), do: {:error, "send one skill id per skill"}

  @doc """
  Gives every skill of the cast `ranks` a stable id (ADR-400 follow-up),
  so a tick survives a rename or a new order. An id sent is kept unless the
  rank already used it; a skill without one takes the id of a skill with
  the same text on the same rank before (`existing`, the stored ranks), and
  otherwise a new id. `new_id` makes ids (a UUID generator).
  """
  def assign_skill_ids(ranks, existing, new_id \\ &Ecto.UUID.generate/0) do
    before = Map.new(existing, &{&1.id, skill_entries(&1)})
    Enum.map(ranks, &assign_rank_skill_ids(&1, Map.get(before, &1[:id], []), new_id))
  end

  defp assign_rank_skill_ids(
         %{requirements: %{"skills" => skills} = requirements} = rank,
         before,
         new_id
       ) do
    ids = requirements["skill_ids"] || List.duplicate(nil, length(skills))

    {assigned, _used} =
      skills
      |> Enum.zip(ids)
      |> Enum.map_reduce(MapSet.new(), fn {name, id}, used ->
        id =
          if is_binary(id) and not MapSet.member?(used, id),
            do: id,
            else: reuse_id(before, name, ids, used) || new_id.()

        {id, MapSet.put(used, id)}
      end)

    %{rank | requirements: Map.put(requirements, "skill_ids", assigned)}
  end

  defp assign_rank_skill_ids(rank, _before, _new_id), do: rank

  defp reuse_id(before, name, ids, used) do
    Enum.find_value(before, fn {old_id, old_name} ->
      if old_name == name and is_binary(old_id) and old_id not in ids and
           not MapSet.member?(used, old_id),
         do: old_id
    end)
  end

  @doc """
  A rank's skills as `{id, name}` in order; the id is nil for a rank stored
  before skills had ids (or a template).
  """
  def skill_entries(rank) do
    requirements = rank_requirements(rank)
    skills = requirements["skills"] || []
    ids = requirements["skill_ids"] || []

    skills
    |> Enum.with_index()
    |> Enum.map(fn {name, index} -> {Enum.at(ids, index), name} end)
  end

  @doc "The skill of `rank` with this id (or, without an id, this text): `{:ok, {id, name}}` or `:error`."
  def find_skill(rank, skill_id, skill) do
    entries = skill_entries(rank)

    found =
      if is_binary(skill_id) and skill_id != "",
        do: Enum.find(entries, fn {id, _name} -> id == String.downcase(skill_id) end),
        else: Enum.find(entries, fn {_id, name} -> is_binary(skill) and name == skill end)

    if found, do: {:ok, found}, else: :error
  end

  defp rank_requirements(%{requirements: requirements}) when is_map(requirements),
    do: Map.new(requirements, fn {key, value} -> {to_string(key), value} end)

  defp rank_requirements(_rank), do: %{}

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
