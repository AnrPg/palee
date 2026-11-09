defmodule Palee.Infrastructure.Catalog.EctoReferenceStore do
  @moduledoc """
  Postgres reader of the reference catalog (ADR-560). Everything is read by
  one statement, so a copy never mixes two revisions, in one round trip.
  """

  @behaviour Palee.Catalog.Ports.ReferenceStore

  alias Palee.Repo

  @load """
  SELECT json_build_object(
    'revision', s.revision,
    'taxonomy_version', s.taxonomy_version,
    'muscles', (SELECT coalesce(json_agg(json_build_object(
        'id', m.id, 'kind', m.kind, 'parent_id', m.parent_id, 'name', m.name,
        'ta2_ids', m.ta2_ids, 'position', m.position)), '[]') FROM muscles m),
    'qualities', (SELECT coalesce(json_agg(json_build_object(
        'id', q.id, 'position', q.position)), '[]') FROM fitness_qualities q),
    'exercises', (SELECT coalesce(json_agg(json_build_object(
        'id', e.id, 'label', e.label, 'category', e.category, 'origin', e.origin,
        'position', e.position,
        'inserted_at', (extract(epoch FROM e.inserted_at) * 1000000)::bigint)), '[]')
      FROM exercises e),
    'aliases', (SELECT coalesce(json_agg(json_build_object(
        'exercise_id', a.exercise_id, 'alias', a.alias, 'kind', a.kind,
        'position', a.position)), '[]') FROM exercise_aliases a),
    'muscle_targets', (SELECT coalesce(json_agg(json_build_object(
        'exercise_id', t.exercise_id, 'muscle_id', t.muscle_id, 'role', t.role)), '[]')
      FROM exercise_muscle_targets t),
    'quality_targets', (SELECT coalesce(json_agg(json_build_object(
        'exercise_id', t.exercise_id, 'quality_id', t.quality_id)), '[]')
      FROM exercise_quality_targets t)
  )
  FROM reference_catalog_state s
  """

  @keys ~w(revision taxonomy_version muscles qualities exercises aliases muscle_targets
           quality_targets id kind parent_id name ta2_ids position label category origin
           inserted_at exercise_id alias muscle_id role quality_id)a

  @impl true
  def load do
    case Repo.query(@load) do
      {:ok, %{rows: [[json]]}} -> {:ok, atomize(decode(json))}
      {:ok, %{rows: []}} -> {:error, :reference_catalog_missing}
      {:error, error} -> {:error, error}
    end
  rescue
    error in [DBConnection.ConnectionError] -> {:error, error}
  end

  @impl true
  def revision do
    case Repo.query("SELECT revision FROM reference_catalog_state") do
      {:ok, %{rows: [[revision]]}} -> {:ok, revision}
      {:ok, %{rows: []}} -> {:error, :reference_catalog_missing}
      {:error, error} -> {:error, error}
    end
  rescue
    error in [DBConnection.ConnectionError] -> {:error, error}
  end

  defp decode(json) when is_binary(json), do: Jason.decode!(json)
  defp decode(json), do: json

  @known Map.new(@keys, &{Atom.to_string(&1), &1})

  # Only the known keys become atoms; values stay as stored.
  defp atomize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {Map.get(@known, key, key), atomize(value)} end)

  defp atomize(list) when is_list(list), do: Enum.map(list, &atomize/1)
  defp atomize(value), do: value
end
