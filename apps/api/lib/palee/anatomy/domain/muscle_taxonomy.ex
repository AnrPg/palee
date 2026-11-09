defmodule Palee.Anatomy.Domain.MuscleTaxonomy do
  @moduledoc """
  The muscle tree for WOD goals, the anatomy atlas and muscle coverage
  (ADR-163): region -> group -> head.

  ADR-560: the tree lives in the `muscles` reference table and is read through
  `Palee.Catalog.reference/0`. Every group and head carries the Terminologia
  Anatomica 2 ids of the meshes that draw it in the atlas asset (ADR-164,
  anatomy-models `ta2-<id>.<side>` nodes), so the API, the atlas and coverage
  share one vocabulary. A group's meshes are its own plus its heads'.

  Ids are stable slugs. Names may change, but an id is never reassigned to a
  different muscle; a migration that adds or removes nodes bumps
  `reference_catalog_state.taxonomy_version` so stored goals can be migrated
  or re-suggested. Display names are translated on the client
  (`anatomy.<id>`); `name` here is the English reference name.

  Only muscles that training loads in a way worth showing are in the tree.
  Meshes outside it (face, eye, pelvic floor, intrinsic hand and foot muscles)
  render neutral in the atlas.
  """

  alias Palee.Catalog.Domain.Reference

  defp reference, do: Palee.Catalog.reference()

  @doc "Taxonomy version; bumped whenever a node is added or removed."
  def version, do: reference().taxonomy_version

  @doc "Every node in tree order (region, then its groups, each followed by its heads)."
  def nodes, do: reference().nodes

  def fetch(id), do: Reference.fetch_node(reference(), id)

  def known?(id), do: fetch(id) != nil

  @doc "Ids that may be targeted by goals and feedback: groups and heads (regions are views)."
  def targetable?(id) do
    case fetch(id) do
      %{kind: kind} when kind in [:group, :head] -> true
      _other -> false
    end
  end

  def regions, do: Enum.filter(nodes(), &(&1.kind == :region))
  def groups, do: Enum.filter(nodes(), &(&1.kind == :group))

  def children(id), do: Reference.children(reference(), id)

  @doc "Position of a node in tree order (unknown ids sort last)."
  def order(id), do: Reference.node_order(reference(), id)

  @doc """
  The group a target rolls up to (a group is its own group). Coverage and the
  goal summary count at group level, the atlas drills down to heads.
  """
  def group_of(id) do
    case fetch(id) do
      %{kind: :group} -> id
      %{kind: :head, group_id: group_id} -> group_id
      _other -> nil
    end
  end

  @doc "The heads of a group; a group without heads is its own single head."
  def heads_of(group_id) do
    case children(group_id) do
      [] -> if known?(group_id), do: [group_id], else: []
      heads -> Enum.map(heads, & &1.id)
    end
  end
end
