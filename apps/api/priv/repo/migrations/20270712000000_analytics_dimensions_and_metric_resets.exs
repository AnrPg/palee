defmodule Palee.Repo.Migrations.AnalyticsDimensionsAndMetricResets do
  @moduledoc """
  ADR-462: staff analytics filters, dimension snapshots and metric resets.

    * Dimension snapshots. `analytics_events`, `class_attendance_records`
      and `attendance_records` record the hot filter dimensions as they were
      when the fact happened: the branch (`location_id`), the class type
      (`class_type_id`), its difficulty (`level`), the coach
      (`coach_user_id`), the person's package family (`package_family`) and,
      on attendance, when the class started (`class_starts_at`, for the
      time-of-day filter). The rest goes in `dimensions` (jsonb). History
      then stays right when a class is moved, re-typed or re-coached, or a
      package changes. Filter columns are indexed per organization.
    * The backfill is plain SQL (no function, no extension setting), run as
      the migration role: forced RLS is lifted for the statements and put
      back, as ADR-400's follow-up did. Facts without a class keep NULLs;
      the summaries fall back to the live class row for those.
    * `analytics_metric_resets`: per-metric baselines. A reset never deletes
      data; every metric counts only data after its active baseline. Rows
      are staff baselines (`scope = 'organization'`, the box's) or a
      member's own (`scope = 'member'`, account-level, `user_id`). Forced
      RLS: the box's rows in its scope, a member's rows in theirs.
  """

  use Ecto.Migration

  @fact_tables [:analytics_events, :class_attendance_records, :attendance_records]
  @read_tables ~w(scheduled_classes class_types memberships membership_package_subscriptions)

  def up do
    for table <- @fact_tables do
      alter table(table) do
        add :location_id, :binary_id
        add :class_type_id, :binary_id
        add :level, :string, size: 16
        add :coach_user_id, :binary_id
        add :package_family, :string, size: 40
        add :dimensions, :map, null: false, default: %{}
      end
    end

    for table <- [:class_attendance_records, :attendance_records] do
      alter table(table) do
        add :class_starts_at, :utc_datetime
      end
    end

    for column <- [:location_id, :class_type_id, :coach_user_id, :package_family] do
      create index(:analytics_events, [:organization_id, column, :occurred_at],
               where: "#{column} IS NOT NULL"
             )

      create index(:class_attendance_records, [:organization_id, column],
               where: "#{column} IS NOT NULL"
             )
    end

    create index(:class_attendance_records, [:organization_id, :class_starts_at])
    create index(:attendance_records, [:organization_id, :class_starts_at])

    flush()
    backfill()

    create table(:analytics_metric_resets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scope, :string, size: 16, null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :metric_key, :string, size: 80, null: false
      add :reset_at, :utc_datetime_usec, null: false
      add :reset_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :undone_at, :utc_datetime_usec
      add :undone_by, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:analytics_metric_resets, :analytics_metric_resets_scope_check,
             check:
               "(scope = 'organization' AND organization_id IS NOT NULL AND user_id IS NULL) OR " <>
                 "(scope = 'member' AND user_id IS NOT NULL AND organization_id IS NULL)"
           )

    create constraint(:analytics_metric_resets, :analytics_metric_resets_undo_check,
             check: "undone_at IS NULL OR undone_at >= reset_at"
           )

    create index(:analytics_metric_resets, [:organization_id, :metric_key, :reset_at],
             where: "scope = 'organization'"
           )

    create index(:analytics_metric_resets, [:user_id, :metric_key, :reset_at],
             where: "scope = 'member'"
           )

    tenant = "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid"
    owner = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY analytics_metric_resets_tenant_policy ON analytics_metric_resets
    USING (scope = 'organization' AND #{tenant})
    WITH CHECK (scope = 'organization' AND #{tenant})
    """)

    execute("""
    CREATE POLICY analytics_metric_resets_member_policy ON analytics_metric_resets
    USING (scope = 'member' AND #{owner})
    WITH CHECK (scope = 'member' AND #{owner})
    """)

    execute("ALTER TABLE analytics_metric_resets ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE analytics_metric_resets FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:analytics_metric_resets)

    for table <- [:class_attendance_records, :attendance_records] do
      alter table(table) do
        remove :class_starts_at
      end
    end

    for table <- @fact_tables do
      alter table(table) do
        remove :location_id
        remove :class_type_id
        remove :level
        remove :coach_user_id
        remove :package_family
        remove :dimensions
      end
    end
  end

  # The package family a person held on a day: their base subscription
  # (not an add-on) that covered it, the latest started first.
  defp family_at(user, day) do
    """
    (SELECT s.package_family_snapshot
       FROM membership_package_subscriptions s
       JOIN memberships m ON m.id = s.membership_id
      WHERE m.user_id = #{user} AND m.organization_id = s.organization_id
        AND s.base_subscription_id IS NULL
        AND s.starts_on <= #{day}
        AND (s.ends_on IS NULL OR s.ends_on >= #{day})
      ORDER BY s.starts_on DESC
      LIMIT 1)
    """
  end

  defp backfill do
    tables = Enum.map(@fact_tables, &to_string/1) ++ @read_tables

    for table <- tables, do: execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")

    for table <- ~w(class_attendance_records attendance_records) do
      execute("""
      UPDATE #{table} AS r
         SET location_id = c.location_id,
             class_type_id = c.class_type_id,
             level = t.level,
             coach_user_id = c.coach_user_id,
             class_starts_at = c.scheduled_at,
             dimensions = jsonb_strip_nulls(jsonb_build_object('space_id', c.space_id,
                                                               'class_series_id', c.class_series_id,
                                                               'class_kind', t.kind))
        FROM scheduled_classes c
        LEFT JOIN class_types t ON t.id = c.class_type_id
       WHERE c.id = r.scheduled_class_id
      """)

      execute("""
      UPDATE #{table} AS r
         SET package_family = #{family_at("r.user_id", "COALESCE(r.class_starts_at, r.marked_at)::date")}
       WHERE r.package_family IS NULL
      """)
    end

    # Events about a class: the class is the subject (`scheduled_class`) or
    # named in the metadata (bookings, attendance, trials).
    execute("""
    UPDATE analytics_events AS e
       SET location_id = c.location_id,
           class_type_id = c.class_type_id,
           level = t.level,
           coach_user_id = c.coach_user_id,
           dimensions = jsonb_strip_nulls(jsonb_build_object('space_id', c.space_id,
                                                             'class_starts_at', c.scheduled_at))
      FROM scheduled_classes c
      LEFT JOIN class_types t ON t.id = c.class_type_id
     WHERE c.organization_id = e.organization_id
       AND c.id = CASE
             WHEN e.context_type = 'scheduled_class' THEN e.context_id
             WHEN e.metadata->>'scheduled_class_id' ~ '^[0-9a-f-]{36}$'
               THEN (e.metadata->>'scheduled_class_id')::uuid
           END
    """)

    # Events naming a branch themselves (stock moves, check-ins).
    execute("""
    UPDATE analytics_events AS e
       SET location_id = (e.metadata->>'location_id')::uuid
     WHERE e.location_id IS NULL
       AND e.metadata->>'location_id' ~ '^[0-9a-f-]{36}$'
    """)

    execute("""
    UPDATE analytics_events AS e
       SET package_family = #{family_at("e.user_id", "e.occurred_at::date")}
     WHERE e.user_id IS NOT NULL AND e.organization_id IS NOT NULL
    """)

    for table <- tables, do: execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
  end
end
