defmodule Palee.Catalog do
  @moduledoc """
  ADR-560: the reference catalog (exercises, muscles, fitness qualities and
  exercise targets) lives in Postgres; every API pod keeps one indexed copy
  in `:persistent_term`, read without copying.

  - `reference/0` is what the domain reads (`MuscleTaxonomy`,
    `FitnessQualities`, `ExerciseCatalog`, `ExerciseTargets`).
  - `refresh/0` reloads it in the calling process (so a test's sandbox
    connection is used) right after a write to the tables.
  - `Palee.Catalog.Cache` loads it at boot and polls the revision, so the
    other pods pick a change up within one poll interval.
  - When the database cannot be read and no copy is loaded yet, the copy is
    built from the seed file the tables were created from, so the API keeps
    working (logged as an error) until the next successful poll.
  """

  require Logger

  alias Palee.Catalog.Domain.Reference
  alias Palee.Catalog.ReferenceStore

  @key {__MODULE__, :reference}
  @seed "priv/repo/reference/exercise_catalog_seed_2027_11_09.json"

  @doc "The current reference copy; loaded on first use when the cache has not run."
  @spec reference() :: Reference.t()
  def reference do
    case :persistent_term.get(@key, nil) do
      %Reference{} = reference -> reference
      nil -> refresh()
    end
  end

  @doc "Reloads the copy from the store; keeps the loaded one (or the seed) on failure."
  @spec refresh() :: Reference.t()
  def refresh do
    case ReferenceStore.load() do
      {:ok, rows} ->
        put(build(rows))

      {:error, reason} ->
        Logger.error(
          "reference catalog: load failed, keeping the previous copy: #{inspect(reason)}"
        )

        :persistent_term.get(@key, nil) || put(seed())
    end
  end

  @doc "Reloads only when the stored revision moved past the loaded one."
  @spec refresh_if_stale() :: :unchanged | :refreshed | {:error, term()}
  def refresh_if_stale do
    loaded = :persistent_term.get(@key, nil)

    case ReferenceStore.revision() do
      {:ok, revision} when is_struct(loaded, Reference) and loaded.revision == revision ->
        :unchanged

      {:ok, _revision} ->
        refresh()
        :refreshed

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Installs a copy (tests restore the copy they started with)."
  @spec put(Reference.t()) :: Reference.t()
  def put(%Reference{} = reference) do
    :persistent_term.put(@key, reference)
    reference
  end

  @doc "The copy built from the seed file (fallback, and for comparison in tests)."
  @spec seed() :: Reference.t()
  def seed do
    data = Application.app_dir(:palee, @seed) |> File.read!() |> Jason.decode!()

    exercises = data["exercises"]

    build(%{
      revision: 0,
      taxonomy_version: data["taxonomy_version"],
      muscles:
        Enum.map(data["muscles"], fn m ->
          %{
            id: m["id"],
            kind: m["kind"],
            parent_id: m["parent_id"],
            name: m["name"],
            ta2_ids: m["ta2_ids"],
            position: m["position"]
          }
        end),
      qualities: Enum.map(data["qualities"], &%{id: &1["id"], position: &1["position"]}),
      exercises:
        Enum.map(exercises, fn e ->
          %{
            id: e["id"],
            label: e["label"],
            category: e["category"],
            origin: "builtin",
            position: e["position"]
          }
        end),
      aliases:
        Enum.flat_map(exercises, fn e ->
          own = Reference.normalize_name(e["label"])

          resolve =
            e["aliases"]
            |> Enum.reject(&(Reference.normalize_name(&1) == own))
            |> Enum.with_index()
            |> Enum.map(fn {name, i} ->
              %{exercise_id: e["id"], alias: name, kind: "resolve", position: i}
            end)

          search =
            e["search_aliases"]
            |> Enum.with_index()
            |> Enum.map(fn {name, i} ->
              %{exercise_id: e["id"], alias: name, kind: "search", position: i}
            end)

          resolve ++ search
        end),
      muscle_targets:
        Enum.flat_map(exercises, fn e ->
          Enum.map(e["muscles"], &%{exercise_id: e["id"], muscle_id: &1["id"], role: &1["role"]})
        end),
      quality_targets:
        Enum.flat_map(exercises, fn e ->
          Enum.map(e["qualities"], &%{exercise_id: e["id"], quality_id: &1})
        end)
    })
  end

  defp build(rows),
    do:
      Reference.build(rows, &Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog.capabilities_for/1)
end
