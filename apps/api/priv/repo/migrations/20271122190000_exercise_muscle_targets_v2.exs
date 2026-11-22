defmodule Palee.Repo.Migrations.ExerciseMuscleTargetsV2 do
  @moduledoc """
  ADR-731: muscle taxonomy v2 and a re-audited exercise → muscle map.

  - Taxonomy: every v1 node keeps its id, kind and parent (saved goals,
    journals and coverage stay valid). New groups, heads and the «Feet»
    region are added; some head-less groups gain heads, and their meshes move
    to those heads (a group draws its own meshes plus its heads'). Positions
    are renumbered to the v2 tree order. `taxonomy_version` becomes 2.
  - Targets of each built-in exercise: when they are still exactly the
    2027-11-09 seed, they are replaced by the v2 audit; when the Palee team
    edited them in the vendor console, the v2 audit is only folded in upwards
    (a missing muscle is added, a weaker role promoted; nothing removed), so
    an edit is never lost.

  Both seeds are read from `priv/repo/reference/` (the v1 file stays as the
  record the first migration was built from).
  """

  use Ecto.Migration

  @v1 "priv/repo/reference/exercise_catalog_seed_2027_11_09.json"
  @v2 "priv/repo/reference/exercise_catalog_seed_2027_11_22.json"
  @rank %{"primary" => 3, "secondary" => 2, "stabilizer" => 1}

  def up do
    v1 = read(@v1)
    v2 = read(@v2)

    put_taxonomy(v2)

    kinds = Map.new(v2["muscles"], &{&1["id"], &1["kind"]})
    parents = Map.new(v2["muscles"], &{&1["id"], &1["parent_id"]})
    v1_targets = Map.new(v1["exercises"], &{&1["id"], target_set(&1["muscles"])})

    for exercise <- v2["exercises"], builtin?(exercise["id"]) do
      current = current_targets(exercise["id"])
      wanted = exercise["muscles"]

      if target_set(current) == Map.get(v1_targets, exercise["id"]) do
        replace_targets(exercise["id"], wanted, kinds)
      else
        merge_up(exercise["id"], current, wanted, kinds, parents)
      end
    end
  end

  def down do
    v1 = read(@v1)
    v2 = read(@v2)

    kinds = Map.new(v1["muscles"], &{&1["id"], &1["kind"]})
    v2_targets = Map.new(v2["exercises"], &{&1["id"], target_set(&1["muscles"])})
    v1_ids = MapSet.new(v1["muscles"], & &1["id"])
    new_ids = for m <- v2["muscles"], not MapSet.member?(v1_ids, m["id"]), do: m["id"]

    for exercise <- v1["exercises"], builtin?(exercise["id"]) do
      if target_set(current_targets(exercise["id"])) == Map.get(v2_targets, exercise["id"]) do
        replace_targets(exercise["id"], exercise["muscles"], kinds)
      end
    end

    # Targets the console put on v2-only muscles have no v1 node to stay on.
    execute_sql("DELETE FROM exercise_muscle_targets WHERE muscle_id = ANY($1)", [new_ids])
    put_taxonomy(v1)

    # Children first (heads, then groups, then regions).
    for kind <- ["head", "group", "region"] do
      execute_sql("DELETE FROM muscles WHERE kind = $1 AND id = ANY($2)", [kind, new_ids])
    end
  end

  defp read(path), do: Application.app_dir(:palee, path) |> File.read!() |> Jason.decode!()

  # Upserts every node of `seed` in tree order (parents first) with its name,
  # meshes and position; ids and kinds never change.
  defp put_taxonomy(seed) do
    execute_sql("UPDATE muscles SET position = position + 100000", [])

    for m <- seed["muscles"] do
      execute_sql(
        """
        INSERT INTO muscles (id, kind, parent_id, name, ta2_ids, position)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (id) DO UPDATE
          SET name = EXCLUDED.name, ta2_ids = EXCLUDED.ta2_ids, position = EXCLUDED.position
        """,
        [m["id"], m["kind"], m["parent_id"], m["name"], m["ta2_ids"], m["position"]]
      )
    end

    execute_sql("UPDATE reference_catalog_state SET taxonomy_version = $1", [
      seed["taxonomy_version"]
    ])
  end

  defp builtin?(id) do
    %{rows: rows} =
      execute_sql("SELECT 1 FROM exercises WHERE id = $1 AND origin = 'builtin'", [id])

    rows != []
  end

  defp current_targets(exercise_id) do
    %{rows: rows} =
      execute_sql(
        "SELECT muscle_id, role FROM exercise_muscle_targets WHERE exercise_id = $1",
        [exercise_id]
      )

    Enum.map(rows, fn [id, role] -> %{"id" => id, "role" => role} end)
  end

  defp target_set(muscles), do: MapSet.new(muscles, &{&1["id"], &1["role"]})

  defp replace_targets(exercise_id, muscles, kinds) do
    execute_sql("DELETE FROM exercise_muscle_targets WHERE exercise_id = $1", [exercise_id])
    Enum.each(muscles, &insert_target(exercise_id, &1, kinds))
  end

  # Only upwards: add what is missing, promote a weaker role, remove nothing.
  # A head is not added when its group already holds an equal or stronger role.
  defp merge_up(exercise_id, current, wanted, kinds, parents) do
    held = Map.new(current, &{&1["id"], &1["role"]})

    Enum.reduce(wanted, held, fn %{"id" => id, "role" => role} = target, held ->
      group = if kinds[id] == "head", do: parents[id], else: id

      cond do
        group != id and Map.has_key?(held, group) and @rank[held[group]] >= @rank[role] ->
          held

        not Map.has_key?(held, id) ->
          insert_target(exercise_id, target, kinds)
          Map.put(held, id, role)

        @rank[role] > @rank[held[id]] ->
          execute_sql(
            "UPDATE exercise_muscle_targets SET role = $3 WHERE exercise_id = $1 AND muscle_id = $2",
            [exercise_id, id, role]
          )

          Map.put(held, id, role)

        true ->
          held
      end
    end)
  end

  defp insert_target(exercise_id, %{"id" => id, "role" => role}, kinds) do
    execute_sql(
      """
      INSERT INTO exercise_muscle_targets (exercise_id, muscle_id, muscle_kind, role)
      VALUES ($1, $2, $3, $4)
      """,
      [exercise_id, id, Map.fetch!(kinds, id), role]
    )
  end

  defp execute_sql(sql, params), do: repo().query!(sql, params)
end
