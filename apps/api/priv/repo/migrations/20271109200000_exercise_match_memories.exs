defmodule Palee.Repo.Migrations.ExerciseMatchMemories do
  @moduledoc """
  ADR-570: what a box's coaches confirmed before publishing a free-text
  workout: «this written name is that catalog exercise» (`folded` written
  text → `exercise_ref`). The next workout of the box offers the same match
  already answered «Ναι»; the coach can still change it, and a «Όχι» to a
  remembered match forgets it. Tenant content under the bare tenant policy,
  like `workout_goals`.
  """

  use Ecto.Migration

  def up do
    create table(:exercise_match_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :folded, :text, null: false
      add :exercise_ref, :text, null: false
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:exercise_match_memories, [:organization_id, :folded])

    create constraint(:exercise_match_memories, :exercise_match_memories_text_check,
             check:
               "char_length(folded) BETWEEN 1 AND 120 AND char_length(exercise_ref) BETWEEN 1 AND 80"
           )

    execute("""
    CREATE TRIGGER exercise_match_memories_apply_tenant_context
    BEFORE INSERT OR UPDATE ON exercise_match_memories
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY exercise_match_memories_tenant_policy ON exercise_match_memories
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE exercise_match_memories ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE exercise_match_memories FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:exercise_match_memories)
  end
end
