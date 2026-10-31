defmodule Palee.Repo.Migrations.WatchLinksAndHeartRate do
  @moduledoc """
  ADR-375 (CP-D8, «Ρολόι»): the person's paired watches (Apple Watch,
  Wear OS) and the heart rate a watch recorded during an execution, sent
  by the phone in numbered batches (idempotent). Both are the person's own;
  heart rate is health data (consent `health_data`) and nobody else reads it.
  """

  use Ecto.Migration

  @tables ~w(watch_links execution_heart_rate_batches)

  def up do
    create table(:watch_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :platform, :string, size: 16, null: false
      add :device_name, :string, size: 60
      add :app_version, :string, size: 32
      add :contract_version, :integer, null: false
      add :settings, :map, null: false, default: %{}
      add :paired_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:watch_links, [:user_id, :platform])

    create constraint(:watch_links, :watch_links_check,
             check: "platform IN ('apple_watch', 'wear_os') AND contract_version >= 1"
           )

    create table(:execution_heart_rate_batches, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :execution_id, references(:workout_executions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :platform, :string, size: 16, null: false
      add :sequence, :integer, null: false
      add :started_offset_ms, :bigint, null: false
      add :interval_ms, :integer, null: false
      add :bpm, {:array, :smallint}, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:execution_heart_rate_batches, [:execution_id, :sequence])
    create index(:execution_heart_rate_batches, [:user_id])

    create constraint(:execution_heart_rate_batches, :execution_heart_rate_batches_check,
             check: """
             platform IN ('apple_watch', 'wear_os') AND sequence >= 0
             AND started_offset_ms >= 0 AND interval_ms BETWEEN 1000 AND 60000
             AND cardinality(bpm) BETWEEN 1 AND 720
             """
           )

    for table <- @tables do
      execute("""
      CREATE POLICY #{table}_owner_policy ON #{table}
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  def down do
    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
  end
end
