defmodule Palee.Repo.Migrations.ExecutionSplits do
  @moduledoc """
  ADR-374 (CP-D7, «Ο προηγούμενος εαυτός σου»): the split marks of an
  execution — the end of each timed segment and each round the athlete taps —
  so the next attempt at the same WOD can run against them.

  Personal table: the owner writes; whoever may read the execution (the
  owner, the box's staff per the executions policy) may read its splits.
  """

  use Ecto.Migration

  def up do
    create table(:execution_splits, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :execution_id,
          references(:workout_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :segment_index, :integer, null: false
      add :section_id, :string, size: 120, null: false
      add :section_ordinal, :integer, null: false
      add :phase, :string, size: 16, null: false
      add :round, :integer, null: false, default: 0
      add :elapsed_ms, :bigint, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:execution_splits, [:execution_id, :segment_index, :round])
    create index(:execution_splits, [:user_id])

    create constraint(:execution_splits, :execution_splits_check,
             check: """
             segment_index >= 0 AND section_ordinal >= 0 AND round >= 0 AND round <= 1000000
             AND elapsed_ms >= 0 AND elapsed_ms <= 2592000000
             AND phase IN ('work', 'rest', 'transition')
             """
           )

    execute("""
    CREATE POLICY execution_splits_owner_policy ON execution_splits
    USING (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR EXISTS (SELECT 1 FROM workout_executions e WHERE e.id = execution_splits.execution_id)
    )
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE execution_splits ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE execution_splits FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:execution_splits)
  end
end
