defmodule Palee.Repo.Migrations.CreateServiceStatus do
  @moduledoc """
  ADR-364 (CP-G4): the public status page.

    * `status_component_states` – the latest probe result of each component
      (database, cache, jobs, search, file storage, email, payments, fiscal
      gateways): one row per component, overwritten by every probe.
    * `status_daily_samples` – how many probes of a component ran on a UTC
      day and how many found it up, degraded or down. 90 days are kept; the
      uptime history is computed from them.
    * `status_incidents` – incidents and planned maintenance the Palee team
      publishes from the platform console, with impact and the components
      they touch.
    * `status_incident_updates` – the timeline of an incident (each status
      change with its note).
    * `status_subscribers` – email addresses that asked to hear about
      incidents (double opt-in). Only the address, its language and the
      confirmation time are kept; an unsubscribe deletes the row.

  Platform data, not tenant data (no `organization_id`): incidents, their
  updates, component states and samples are public (anyone reads them, so
  the page works without sign-in or from a host outside the cluster);
  only vendors or system sessions (no acting user: the probe job, the
  public subscribe flow) write them. Subscribers are never readable by an
  ordinary signed-in user.
  """

  use Ecto.Migration

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @public_tables ~w(status_component_states status_daily_samples status_incidents status_incident_updates)

  def up do
    create table(:status_component_states, primary_key: false) do
      add :component, :text, primary_key: true
      add :status, :text, null: false
      add :reason, :text
      add :checked_at, :utc_datetime_usec, null: false
      add :changed_at, :utc_datetime_usec, null: false
    end

    create constraint(:status_component_states, :status_component_states_status_check,
             check: "status IN ('operational', 'degraded', 'down')"
           )

    create constraint(:status_component_states, :status_component_states_reason_check,
             check: "reason IS NULL OR char_length(reason) <= 300"
           )

    create table(:status_daily_samples, primary_key: false) do
      add :component, :text, null: false, primary_key: true
      add :day, :date, null: false, primary_key: true
      add :total, :integer, null: false, default: 0
      add :operational, :integer, null: false, default: 0
      add :degraded, :integer, null: false, default: 0
      add :down, :integer, null: false, default: 0
    end

    create index(:status_daily_samples, [:day])

    create constraint(:status_daily_samples, :status_daily_samples_counts_check,
             check:
               "total >= 0 AND operational >= 0 AND degraded >= 0 AND down >= 0 " <>
                 "AND operational + degraded + down = total"
           )

    create table(:status_incidents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :text, null: false
      add :title, :text, null: false
      add :impact, :text, null: false
      add :status, :text, null: false
      add :components, {:array, :text}, null: false, default: []
      add :scheduled_for, :utc_datetime_usec
      add :scheduled_until, :utc_datetime_usec
      add :started_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create index(:status_incidents, [:started_at])
    create index(:status_incidents, [:resolved_at])

    create constraint(:status_incidents, :status_incidents_check,
             check: """
             kind IN ('incident', 'maintenance')
             AND impact IN ('none', 'minor', 'major', 'critical')
             AND char_length(title) BETWEEN 3 AND 140
             AND (
               (kind = 'incident' AND status IN ('investigating', 'identified', 'monitoring', 'resolved'))
               OR (kind = 'maintenance' AND status IN ('scheduled', 'in_progress', 'completed')
                   AND scheduled_for IS NOT NULL AND scheduled_until IS NOT NULL
                   AND scheduled_until > scheduled_for)
             )
             AND ((status IN ('resolved', 'completed')) = (resolved_at IS NOT NULL))
             """
           )

    create table(:status_incident_updates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :incident_id, references(:status_incidents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :text, null: false
      add :body, :text, null: false
      add :notify, :boolean, null: false, default: true
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:status_incident_updates, [:incident_id, :inserted_at])

    create constraint(:status_incident_updates, :status_incident_updates_body_check,
             check: "char_length(body) BETWEEN 1 AND 2000"
           )

    create table(:status_subscribers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :text, null: false
      add :email_digest, :text, null: false
      add :locale, :text, null: false, default: "en"
      add :confirm_token_digest, :text
      add :confirmed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:status_subscribers, [:email_digest])
    create unique_index(:status_subscribers, [:confirm_token_digest])
    create index(:status_subscribers, [:confirmed_at])

    create constraint(:status_subscribers, :status_subscribers_check,
             check:
               "char_length(email) BETWEEN 3 AND 254 AND char_length(locale) BETWEEN 2 AND 8 " <>
                 "AND (confirmed_at IS NOT NULL OR confirm_token_digest IS NOT NULL)"
           )

    for table <- @public_tables do
      execute("""
      CREATE POLICY #{table}_read_policy ON #{table}
        FOR SELECT
        USING (true)
      """)

      execute("""
      CREATE POLICY #{table}_write_policy ON #{table}
        FOR ALL
        USING (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
        WITH CHECK (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    # Subscribers: system sessions (the public subscribe flow and the
    # notification job run without an acting user) and vendors only.
    execute("""
    CREATE POLICY status_subscribers_policy ON status_subscribers
      FOR ALL
      USING (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
      WITH CHECK (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
    """)

    execute("ALTER TABLE status_subscribers ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE status_subscribers FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:status_subscribers)
    drop table(:status_incident_updates)
    drop table(:status_incidents)
    drop table(:status_daily_samples)
    drop table(:status_component_states)
  end
end
