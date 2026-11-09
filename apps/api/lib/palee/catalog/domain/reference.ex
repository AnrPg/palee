defmodule Palee.Catalog.Domain.Reference do
  @moduledoc """
  ADR-560: one immutable, indexed copy of the reference catalog: the muscle
  taxonomy, the fitness qualities, the exercises with their aliases, and the
  muscles (by role) and qualities each exercise trains.

  Built from the rows the reference store loads (`build/1`); every lookup the
  domain makes (`MuscleTaxonomy`, `FitnessQualities`, `ExerciseCatalog`,
  `ExerciseTargets`) is answered from the indexes precomputed here, so a read
  costs what the code-owned module attributes it replaces cost. Pure.
  """

  @roles [:primary, :secondary, :stabilizer]
  @role_rank %{primary: 3, secondary: 2, stabilizer: 1}
  @categories ~w(strength bodyweight cardio mobility skill)

  @enforce_keys [:revision, :taxonomy_version]
  defstruct revision: 0,
            taxonomy_version: 1,
            nodes: [],
            node_by_id: %{},
            children: %{},
            node_order: %{},
            qualities: [],
            exercises: [],
            exercise_by_id: %{},
            resolve_index: %{},
            search_aliases: %{},
            targets: %{}

  @type t :: %__MODULE__{}

  @type rows :: %{
          required(:revision) => non_neg_integer(),
          required(:taxonomy_version) => pos_integer(),
          required(:muscles) => [map()],
          required(:qualities) => [map()],
          required(:exercises) => [map()],
          required(:aliases) => [map()],
          required(:muscle_targets) => [map()],
          required(:quality_targets) => [map()]
        }

  def roles, do: @roles
  def role_rank(role), do: Map.fetch!(@role_rank, role)
  def categories, do: @categories

  @doc """
  Builds the indexed reference from the store's rows (any order).
  `capabilities` maps a category to the Quick Text parameters its exercises
  take (the Workouts context owns that rule).
  """
  @spec build(rows(), (String.t() -> [String.t()])) :: t()
  def build(rows, capabilities \\ fn _category -> [] end) do
    nodes = build_nodes(rows.muscles)
    node_order = nodes |> Enum.with_index() |> Map.new(fn {node, index} -> {node.id, index} end)
    qualities = rows.qualities |> Enum.sort_by(& &1.position) |> Enum.map(& &1.id)
    aliases = Enum.sort_by(rows.aliases, &{&1.exercise_id, &1.position, &1.alias})

    resolve_aliases =
      for(a <- aliases, a.kind == "resolve", do: a) |> Enum.group_by(& &1.exercise_id, & &1.alias)

    search_aliases =
      for(a <- aliases, a.kind == "search", do: a) |> Enum.group_by(& &1.exercise_id, & &1.alias)

    exercises =
      rows.exercises
      |> Enum.sort_by(&{&1.position == nil, &1.position, Map.get(&1, :inserted_at, 0), &1.id})
      |> Enum.map(fn exercise ->
        %{
          id: exercise.id,
          label: exercise.label,
          category: exercise.category,
          origin: exercise.origin,
          aliases: Map.get(resolve_aliases, exercise.id, []),
          capabilities: capabilities.(exercise.category)
        }
      end)

    %__MODULE__{
      revision: rows.revision,
      taxonomy_version: rows.taxonomy_version,
      nodes: nodes,
      node_by_id: Map.new(nodes, &{&1.id, &1}),
      children: nodes |> Enum.reject(&is_nil(&1.parent_id)) |> Enum.group_by(& &1.parent_id),
      node_order: node_order,
      qualities: qualities,
      exercises: exercises,
      exercise_by_id: Map.new(exercises, &{&1.id, &1}),
      resolve_index: resolve_index(exercises),
      search_aliases: search_aliases,
      targets: targets(rows, node_order, qualities)
    }
  end

  @doc "The resolution key of a name (NFC, trimmed, lowercase, `[\\s_-]+` as one space)."
  def normalize_name(name) when is_binary(name) do
    name
    |> String.normalize(:nfc)
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[\s_-]+/u, " ")
  end

  # -- Muscles ------------------------------------------------------------------

  def fetch_node(%__MODULE__{node_by_id: by_id}, id) when is_binary(id), do: Map.get(by_id, id)
  def fetch_node(_reference, _id), do: nil

  def children(%__MODULE__{children: children}, id), do: Map.get(children, id, [])

  def node_order(%__MODULE__{node_order: order}, id), do: Map.get(order, id, 10_000)

  # -- Exercises ----------------------------------------------------------------

  def fetch_exercise(%__MODULE__{exercise_by_id: by_id}, id) when is_binary(id),
    do: Map.get(by_id, id)

  def fetch_exercise(_reference, _id), do: nil

  @doc """
  `{:ok, exercise, :canonical | :alias}` for a label or a resolve alias,
  `{:error, :not_found}` or `{:error, {:ambiguous, ids}}`. Labels win over
  aliases.
  """
  def resolve(%__MODULE__{resolve_index: index} = reference, name) when is_binary(name) do
    key = normalize_name(name)

    case Map.get(index, key) do
      %{labels: [id]} -> {:ok, fetch_exercise(reference, id), :canonical}
      %{labels: [_ | _] = ids} -> {:error, {:ambiguous, ids}}
      %{aliases: [id]} -> {:ok, fetch_exercise(reference, id), :alias}
      %{aliases: [_ | _] = ids} -> {:error, {:ambiguous, ids}}
      _none -> {:error, :not_found}
    end
  end

  def resolve(_reference, _name), do: {:error, :not_found}

  def search_aliases(%__MODULE__{search_aliases: aliases}, id), do: Map.get(aliases, id, [])

  @doc """
  Targets of an exercise: `%{muscles: [%{id, role}], qualities: [id]}`, strongest
  role first then tree order. `nil` when the exercise is unknown or nobody has
  mapped it yet (no muscle and no quality).
  """
  def targets(%__MODULE__{targets: targets}, id) when is_binary(id), do: Map.get(targets, id)
  def targets(_reference, _id), do: nil

  def targeted_ids(%__MODULE__{targets: targets}), do: Map.keys(targets)

  # -- Building -----------------------------------------------------------------

  # Tree order: each region by position, then its groups by position, each
  # followed by its heads; a group's and region's meshes are their subtree's.
  defp build_nodes(muscles) do
    by_parent = Enum.group_by(muscles, & &1.parent_id)
    sorted = fn parent -> by_parent |> Map.get(parent, []) |> Enum.sort_by(& &1.position) end

    Enum.flat_map(sorted.(nil), fn region ->
      groups =
        Enum.flat_map(sorted.(region.id), fn group ->
          heads =
            Enum.map(sorted.(group.id), fn head ->
              node(head, :head, region.id, group.id, head.ta2_ids)
            end)

          [
            node(
              group,
              :group,
              region.id,
              group.id,
              group.ta2_ids ++ Enum.flat_map(heads, & &1.ta2_ids)
            )
            | heads
          ]
        end)

      region_meshes = Enum.flat_map(groups, &if(&1.kind == :group, do: &1.ta2_ids, else: []))
      [node(region, :region, region.id, nil, region_meshes) | groups]
    end)
  end

  defp node(row, kind, region_id, group_id, ta2_ids) do
    %{
      id: row.id,
      kind: kind,
      name: row.name,
      parent_id: row.parent_id,
      region_id: region_id,
      group_id: group_id,
      ta2_ids: ta2_ids
    }
  end

  defp resolve_index(exercises) do
    labels = Enum.map(exercises, &{normalize_name(&1.label), :labels, &1.id})

    aliases =
      for exercise <- exercises,
          name <- exercise.aliases,
          do: {normalize_name(name), :aliases, exercise.id}

    Enum.reduce(labels ++ aliases, %{}, fn {key, kind, id}, acc ->
      Map.update(acc, key, %{kind => [id]}, fn entry ->
        Map.update(entry, kind, [id], &Enum.uniq(&1 ++ [id]))
      end)
    end)
  end

  defp targets(rows, node_order, qualities) do
    muscles = Enum.group_by(rows.muscle_targets, & &1.exercise_id)
    quality_order = qualities |> Enum.with_index() |> Map.new()
    developed = Enum.group_by(rows.quality_targets, & &1.exercise_id, & &1.quality_id)

    rows.exercises
    |> Enum.map(& &1.id)
    |> Enum.filter(&(Map.has_key?(muscles, &1) or Map.has_key?(developed, &1)))
    |> Map.new(fn id ->
      {id,
       %{
         muscles:
           muscles
           |> Map.get(id, [])
           |> Enum.map(&%{id: &1.muscle_id, role: role(&1.role)})
           |> Enum.sort_by(fn %{id: muscle, role: role} ->
             {-role_rank(role), Map.get(node_order, muscle, 10_000)}
           end),
         qualities:
           developed
           |> Map.get(id, [])
           |> Enum.uniq()
           |> Enum.sort_by(&Map.get(quality_order, &1, 100))
       }}
    end)
  end

  defp role("primary"), do: :primary
  defp role("secondary"), do: :secondary
  defp role("stabilizer"), do: :stabilizer
  defp role(role) when role in @roles, do: role
end
