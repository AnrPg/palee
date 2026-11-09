defmodule Palee.Repo.Migrations.CreateReferenceExerciseCatalog do
  @moduledoc """
  ADR-560: the exercise catalog, the muscle taxonomy, the fitness qualities
  and which muscles (by role) and qualities each exercise trains move from
  code into reference tables.

  - `muscles`: the region → group → head tree (ADR-163) with the atlas mesh
    ids (TA2) each node draws itself; a group's own meshes exclude its heads'.
  - `fitness_qualities`: the ten general physical skills.
  - `exercises` + `exercise_aliases`: the catalog. `resolve` aliases are what
    Quick Text resolves (unique across the catalog); `search` aliases only
    feed suggestions (Greek names, abbreviations).
  - `exercise_muscle_targets`: one role per muscle per exercise (`primary`,
    `secondary`, `stabilizer`). A composite foreign key on `(muscle_id,
    muscle_kind)` lets only groups and heads be targets, without a trigger.
  - `exercise_quality_targets`: the qualities an exercise develops.
  - `reference_catalog_state`: one row whose `revision` every write to these
    tables bumps (statement trigger), so every API pod notices a change and
    reloads its in-memory copy; `taxonomy_version` is stamped on saved goals.

  Seeded from `priv/repo/reference/exercise_catalog_seed_2027_11_09.json`
  (the code-owned data as of this migration), then the Palee team's approved
  catalog additions (ADR-461) are carried over: an approved entry becomes an
  exercise without targets yet, an approved alias a `resolve` alias.
  Platform data holding no person: no row-level security, like the other
  platform tables. Names are normalised here with a frozen copy of
  `ExerciseCatalog`'s rule (NFC, trim, lowercase, `[\\s_-]+` → space).
  """

  use Ecto.Migration

  @seed "priv/repo/reference/exercise_catalog_seed_2027_11_09.json"
  @tables ~w(muscles fitness_qualities exercises exercise_aliases exercise_muscle_targets exercise_quality_targets)

  def up do
    create table(:reference_catalog_state, primary_key: false) do
      add :id, :boolean, primary_key: true, default: true
      add :revision, :bigint, null: false, default: 1
      add :taxonomy_version, :integer, null: false
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create constraint(:reference_catalog_state, :reference_catalog_state_singleton_check,
             check: "id"
           )

    create table(:muscles, primary_key: false) do
      add :id, :text, primary_key: true
      add :kind, :text, null: false
      add :parent_id, references(:muscles, column: :id, type: :text, on_delete: :restrict)
      add :name, :text, null: false
      add :ta2_ids, {:array, :text}, null: false, default: []
      add :position, :integer, null: false
    end

    create unique_index(:muscles, [:id, :kind], name: :muscles_id_kind_index)
    create unique_index(:muscles, [:position])

    create constraint(:muscles, :muscles_kind_check,
             check:
               "kind IN ('region', 'group', 'head') AND ((kind = 'region') = (parent_id IS NULL))"
           )

    create constraint(:muscles, :muscles_id_check, check: "id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'")

    create table(:fitness_qualities, primary_key: false) do
      add :id, :text, primary_key: true
      add :position, :integer, null: false
    end

    create unique_index(:fitness_qualities, [:position])

    create table(:exercises, primary_key: false) do
      add :id, :text, primary_key: true
      add :label, :text, null: false
      add :normalized, :text, null: false
      add :category, :text, null: false
      add :origin, :text, null: false
      add :position, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:exercises, [:normalized])

    create constraint(:exercises, :exercises_id_check,
             check: "id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(id) <= 80"
           )

    create constraint(:exercises, :exercises_label_check,
             check: "char_length(label) BETWEEN 1 AND 120 AND char_length(normalized) >= 1"
           )

    create constraint(:exercises, :exercises_category_check,
             check: "category IN ('strength', 'bodyweight', 'cardio', 'mobility', 'skill')"
           )

    create constraint(:exercises, :exercises_origin_check,
             check: "origin IN ('builtin', 'reviewed')"
           )

    create table(:exercise_aliases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :exercise_id, references(:exercises, column: :id, type: :text, on_delete: :delete_all),
        null: false

      add :alias, :text, null: false
      add :normalized, :text, null: false
      add :kind, :text, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:exercise_aliases, [:exercise_id, :kind, :normalized])

    create unique_index(:exercise_aliases, [:normalized],
             where: "kind = 'resolve'",
             name: :exercise_aliases_resolve_normalized_index
           )

    create constraint(:exercise_aliases, :exercise_aliases_kind_check,
             check: "kind IN ('resolve', 'search')"
           )

    create constraint(:exercise_aliases, :exercise_aliases_alias_check,
             check: "char_length(alias) BETWEEN 1 AND 120 AND char_length(normalized) >= 1"
           )

    create table(:exercise_muscle_targets, primary_key: false) do
      add :exercise_id,
          references(:exercises, column: :id, type: :text, on_delete: :delete_all),
          primary_key: true

      add :muscle_id, :text, primary_key: true
      add :muscle_kind, :text, null: false
      add :role, :text, null: false
    end

    execute("""
    ALTER TABLE exercise_muscle_targets
      ADD CONSTRAINT exercise_muscle_targets_muscle_fkey
      FOREIGN KEY (muscle_id, muscle_kind) REFERENCES muscles (id, kind)
      ON UPDATE CASCADE ON DELETE RESTRICT
    """)

    create index(:exercise_muscle_targets, [:muscle_id])

    create constraint(:exercise_muscle_targets, :exercise_muscle_targets_kind_check,
             check: "muscle_kind IN ('group', 'head')"
           )

    create constraint(:exercise_muscle_targets, :exercise_muscle_targets_role_check,
             check: "role IN ('primary', 'secondary', 'stabilizer')"
           )

    create table(:exercise_quality_targets, primary_key: false) do
      add :exercise_id,
          references(:exercises, column: :id, type: :text, on_delete: :delete_all),
          primary_key: true

      add :quality_id,
          references(:fitness_qualities, column: :id, type: :text, on_delete: :restrict),
          primary_key: true
    end

    # Approved additions may now hold a reviewed entry's targets, and the
    # audit trail records target edits.
    drop constraint(:exercise_catalog_audit_events, :exercise_catalog_audit_events_action_check)

    create constraint(:exercise_catalog_audit_events, :exercise_catalog_audit_events_action_check,
             check: "action IN ('approve_entry', 'approve_alias', 'reject', 'set_targets')"
           )

    flush()
    seed()
    carry_over_additions()

    execute("""
    CREATE FUNCTION palee_bump_reference_catalog_revision() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      UPDATE reference_catalog_state SET revision = revision + 1, updated_at = now();
      RETURN NULL;
    END;
    $$
    """)

    for table <- @tables do
      execute("""
      CREATE TRIGGER #{table}_bump_reference_catalog_revision
      AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON #{table}
      FOR EACH STATEMENT EXECUTE FUNCTION palee_bump_reference_catalog_revision()
      """)
    end
  end

  def down do
    for table <- @tables do
      execute("DROP TRIGGER IF EXISTS #{table}_bump_reference_catalog_revision ON #{table}")
    end

    execute("DROP FUNCTION IF EXISTS palee_bump_reference_catalog_revision()")

    execute("DELETE FROM exercise_catalog_audit_events WHERE action = 'set_targets'")
    drop constraint(:exercise_catalog_audit_events, :exercise_catalog_audit_events_action_check)

    create constraint(:exercise_catalog_audit_events, :exercise_catalog_audit_events_action_check,
             check: "action IN ('approve_entry', 'approve_alias', 'reject')"
           )

    drop table(:exercise_quality_targets)
    drop table(:exercise_muscle_targets)
    drop table(:exercise_aliases)
    drop table(:exercises)
    drop table(:fitness_qualities)
    drop table(:muscles)
    drop table(:reference_catalog_state)
  end

  defp seed do
    data = Application.app_dir(:palee, @seed) |> File.read!() |> Jason.decode!()
    now = DateTime.utc_now()

    repo().insert_all("reference_catalog_state", [
      %{id: true, revision: 1, taxonomy_version: data["taxonomy_version"], updated_at: now}
    ])

    # Parents come before their children in tree order.
    for muscle <- data["muscles"] do
      repo().insert_all("muscles", [
        %{
          id: muscle["id"],
          kind: muscle["kind"],
          parent_id: muscle["parent_id"],
          name: muscle["name"],
          ta2_ids: muscle["ta2_ids"],
          position: muscle["position"]
        }
      ])
    end

    repo().insert_all(
      "fitness_qualities",
      Enum.map(data["qualities"], &%{id: &1["id"], position: &1["position"]})
    )

    kinds = Map.new(data["muscles"], &{&1["id"], &1["kind"]})

    for exercise <- data["exercises"] do
      label_key = normalize(exercise["label"])

      repo().insert_all("exercises", [
        %{
          id: exercise["id"],
          label: exercise["label"],
          normalized: label_key,
          category: exercise["category"],
          origin: "builtin",
          position: exercise["position"],
          inserted_at: now,
          updated_at: now
        }
      ])

      aliases =
        alias_rows(exercise["id"], exercise["aliases"], "resolve", [label_key], now) ++
          alias_rows(exercise["id"], exercise["search_aliases"], "search", [], now)

      if aliases != [], do: repo().insert_all("exercise_aliases", aliases)

      muscles =
        Enum.map(exercise["muscles"], fn %{"id" => id, "role" => role} ->
          %{
            exercise_id: exercise["id"],
            muscle_id: id,
            muscle_kind: Map.fetch!(kinds, id),
            role: role
          }
        end)

      if muscles != [], do: repo().insert_all("exercise_muscle_targets", muscles)

      qualities = Enum.map(exercise["qualities"], &%{exercise_id: exercise["id"], quality_id: &1})
      if qualities != [], do: repo().insert_all("exercise_quality_targets", qualities)
    end
  end

  # An alias equal to its own label (after normalising) adds nothing.
  defp alias_rows(exercise_id, aliases, kind, skip, now) do
    aliases
    |> Enum.with_index()
    |> Enum.map(fn {name, index} -> {name, normalize(name), index} end)
    |> Enum.reject(fn {_name, key, _index} -> key in skip end)
    |> Enum.uniq_by(fn {_name, key, _index} -> key end)
    |> Enum.map(fn {name, key, index} ->
      %{
        id: Ecto.UUID.bingenerate(),
        exercise_id: exercise_id,
        alias: name,
        normalized: key,
        kind: kind,
        position: index,
        inserted_at: now
      }
    end)
  end

  defp carry_over_additions do
    %{rows: rows} =
      repo().query!("""
      SELECT kind, catalog_slug, label, category, inserted_at
      FROM exercise_catalog_additions ORDER BY inserted_at, kind DESC
      """)

    Enum.each(rows, fn
      ["entry", slug, label, category, at] ->
        repo().query!(
          """
          INSERT INTO exercises (id, label, normalized, category, origin, inserted_at, updated_at)
          VALUES ($1, $2, $3, $4, 'reviewed', $5, $5)
          ON CONFLICT DO NOTHING
          """,
          [slug, label, normalize(label), category, at]
        )

      ["alias", slug, label, _category, at] ->
        repo().query!(
          """
          INSERT INTO exercise_aliases (id, exercise_id, alias, normalized, kind, position, inserted_at)
          SELECT $1, e.id, $3, $4, 'resolve', 1000, $5 FROM exercises e
          WHERE e.id = $2 AND e.normalized <> $4
            AND NOT EXISTS (SELECT 1 FROM exercises o WHERE o.normalized = $4)
          ON CONFLICT DO NOTHING
          """,
          [Ecto.UUID.bingenerate(), slug, label, normalize(label), at]
        )
    end)
  end

  defp normalize(name) do
    name
    |> String.normalize(:nfc)
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[\s_-]+/u, " ")
  end
end
