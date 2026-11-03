defmodule Palee.Repo.Migrations.WatchOffers do
  @moduledoc """
  ADR-375 amendment (2026-11-03, ANR's D8 rules): when a WOD is opened for
  execution and a watch is connected, the phone asks «Το χρονόμετρο και στο
  ρολόι;». One row per execution remembers whether the question was asked
  (and the answer) or the watch started on its own, so a box member is asked
  on the first five such WODs only. The person's own rows; nobody else
  reads them.
  """

  use Ecto.Migration

  def up do
    create table(:watch_offers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :execution_id,
          references(:workout_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :platform, :string, size: 16, null: false
      add :mode, :string, size: 8, null: false
      add :answer, :string, size: 8
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:watch_offers, [:execution_id])
    create index(:watch_offers, [:user_id, :mode])

    create constraint(:watch_offers, :watch_offers_check,
             check: """
             platform IN ('apple_watch', 'wear_os') AND mode IN ('asked', 'auto')
             AND (answer IS NULL OR (mode = 'asked' AND answer IN ('yes', 'no')))
             """
           )

    execute("""
    CREATE POLICY watch_offers_owner_policy ON watch_offers
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE watch_offers ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE watch_offers FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:watch_offers)
  end
end
