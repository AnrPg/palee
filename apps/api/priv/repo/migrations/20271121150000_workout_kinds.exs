defmodule Palee.Repo.Migrations.WorkoutKinds do
  @moduledoc """
  ADR-690: a box adds its own workout types, and a WOD has several types.

    * `master_workouts.types` / `families`: the WOD's type references and
      their families (backfilled from `type`); `type` becomes a derived,
      nullable compatibility column.
    * `workout_sections.types`: a section's types (sectioned WODs).
    * `training_log_entries.workout_types`: the types of a logged WOD.
    * `organization_workout_kinds`: a box's own types (tenant, RLS).
    * `workout_kind_additions`: kinds the Palee team added for everyone.
    * `workout_kind_candidates`: the Palee team's queue, one row per folded
      name across boxes (box types and public-page discipline suggestions),
      with the decision as its audit trail. No person in it.
    * `palee_workout_kinds_by_ids/1`: box type labels for any reader.
    * Notification type `workout_kind_adopted`.
  """

  use Ecto.Migration

  @notification_types ~w(workout_kind_adopted)
  @families ~w(functional strength gymnastics endurance mind_body combat dance outdoor recovery)

  def up do
    alter table(:master_workouts) do
      add :types, {:array, :text}, null: false, default: []
      add :families, {:array, :text}, null: false, default: []
    end

    execute("ALTER TABLE master_workouts ALTER COLUMN type DROP NOT NULL")

    execute("""
    UPDATE master_workouts
    SET types = ARRAY[type], families = ARRAY[#{family_case("type")}]
    WHERE type IS NOT NULL AND #{family_case("type")} IS NOT NULL
    """)

    execute("CREATE INDEX master_workouts_types_index ON master_workouts USING gin (types)")
    execute("CREATE INDEX master_workouts_families_index ON master_workouts USING gin (families)")

    alter table(:workout_sections) do
      add :types, {:array, :text}, null: false, default: []
    end

    alter table(:training_log_entries) do
      add :workout_types, {:array, :text}, null: false, default: []
    end

    execute("""
    UPDATE training_log_entries SET workout_types = ARRAY[workout_type]
    WHERE workout_type IS NOT NULL AND workout_type <> ''
    """)

    create table(:organization_workout_kinds, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :label, :text, null: false
      add :folded, :text, null: false
      add :family, :text, null: false
      add :status, :text, null: false, default: "active"
      add :merged_into, :text
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_workout_kinds, [:organization_id, :folded],
             where: "status <> 'merged'",
             name: :organization_workout_kinds_folded_index
           )

    create constraint(:organization_workout_kinds, :organization_workout_kinds_status_check,
             check: "status IN ('active', 'hidden', 'merged')"
           )

    create constraint(:organization_workout_kinds, :organization_workout_kinds_merged_check,
             check: "(status = 'merged') = (merged_into IS NOT NULL)"
           )

    create constraint(:organization_workout_kinds, :organization_workout_kinds_label_check,
             check: "char_length(label) BETWEEN 2 AND 40"
           )

    create constraint(:organization_workout_kinds, :organization_workout_kinds_family_check,
             check: "family IN (#{quoted(@families)})"
           )

    execute("""
    CREATE TRIGGER organization_workout_kinds_apply_tenant_context
    BEFORE INSERT OR UPDATE ON organization_workout_kinds
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY organization_workout_kinds_tenant_policy ON organization_workout_kinds
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE organization_workout_kinds ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE organization_workout_kinds FORCE ROW LEVEL SECURITY")

    # The labels of box types for any signed-in reader (a member's journal
    # holds types of several boxes): only what a label needs, never who made
    # it. The only cross-tenant path to the table.
    execute("""
    CREATE FUNCTION palee_workout_kinds_by_ids(kind_ids uuid[])
    RETURNS TABLE (id uuid, label text, family text, status text, merged_into text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
      SELECT k.id, k.label, k.family, k.status, k.merged_into
      FROM organization_workout_kinds k
      WHERE k.id = ANY(kind_ids)
      LIMIT 500
    $$
    """)

    create table(:workout_kind_candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :text, null: false
      add :folded, :text, null: false
      # %{"family" => number of boxes that chose it}
      add :family_votes, :map, null: false, default: %{}
      add :organization_ids, {:array, :binary_id}, null: false, default: []
      add :profile_suggestion_ids, {:array, :binary_id}, null: false, default: []
      add :status, :text, null: false, default: "pending"
      add :decision, :map
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :digested_at, :utc_datetime_usec
      add :decided_at, :utc_datetime_usec
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workout_kind_candidates, [:folded])
    create index(:workout_kind_candidates, [:status, :first_seen_at])

    create constraint(:workout_kind_candidates, :workout_kind_candidates_status_check,
             check: "status IN ('pending', 'adopted', 'aliased', 'kept')"
           )

    create table(:workout_kind_additions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :text, null: false
      add :family, :text, null: false
      # %{"el" => "…", "en" => "…", …}: one label per locale
      add :labels, :map, null: false

      add :candidate_id,
          references(:workout_kind_candidates, type: :binary_id, on_delete: :nilify_all)

      add :added_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:workout_kind_additions, [:key])

    create constraint(:workout_kind_additions, :workout_kind_additions_key_check,
             check: "key ~ '^[a-z][a-z0-9_]{1,47}$'"
           )

    create constraint(:workout_kind_additions, :workout_kind_additions_family_check,
             check: "family IN (#{quoted(@families)})"
           )

    rewrite_notification_types(&Enum.uniq(&1 ++ @notification_types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN (#{Enum.map_join(@notification_types, ", ", &"'#{&1}'")})"
    )

    rewrite_notification_types(&(&1 -- @notification_types))
    drop table(:workout_kind_additions)
    drop table(:workout_kind_candidates)
    execute("DROP FUNCTION IF EXISTS palee_workout_kinds_by_ids(uuid[])")
    drop table(:organization_workout_kinds)

    alter table(:training_log_entries) do
      remove :workout_types
    end

    alter table(:workout_sections) do
      remove :types
    end

    execute("DROP INDEX IF EXISTS master_workouts_families_index")
    execute("DROP INDEX IF EXISTS master_workouts_types_index")

    alter table(:master_workouts) do
      remove :families
      remove :types
    end
  end

  # The built-in kinds' families as they were on 2026-11-21 (ADR-275/400).
  defp family_case(column) do
    whens =
      Palee.Workouts.Domain.WorkoutType.families()
      |> Enum.map_join(" ", fn {family, keys} ->
        "WHEN #{column} IN (#{quoted(keys)}) THEN '#{family}'"
      end)

    "(CASE #{whens} END)"
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
