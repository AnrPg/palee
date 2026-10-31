defmodule Palee.Repo.Migrations.CreateDataQuestions do
  @moduledoc """
  ADR-361: AI questions over a box's data.

    * `organization_ai_settings.data_questions_enabled` – the owner's
      switch (off by default): the box's aggregated data may be sent to the
      platform's model provider to answer staff questions;
    * `data_questions` – the audit log: one row per question, with who
      asked, what, which read queries ran (names, arguments, row counts),
      the answer, its citations and whether every number in it was found
      in the data. Never the rows themselves: people appear only as counts.

  A tenant table: forced RLS and the `palee_apply_tenant_context` trigger.
  """

  use Ecto.Migration

  def up do
    alter table(:organization_ai_settings) do
      add :data_questions_enabled, :boolean, null: false, default: false
    end

    create table(:data_questions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :question, :text, null: false
      add :locale, :text, null: false
      add :status, :text, null: false
      add :error_code, :text
      add :answer, :text
      add :grounded, :boolean, null: false, default: false
      add :unsupported_numbers, {:array, :text}, null: false, default: []
      add :citations, :map, null: false, default: fragment("'[]'::jsonb")
      add :steps, :map, null: false, default: fragment("'[]'::jsonb")
      add :rounds, :integer, null: false, default: 0
      add :model, :text
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :duration_ms, :integer
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:data_questions, [:organization_id, :inserted_at])
    create index(:data_questions, [:organization_id, :user_id, :inserted_at])

    create constraint(:data_questions, :data_questions_check,
             check: """
             char_length(question) BETWEEN 1 AND 500
             AND char_length(locale) BETWEEN 2 AND 5
             AND status IN ('answered', 'unanswerable', 'failed', 'refused')
             AND (answer IS NULL OR char_length(answer) <= 4000)
             AND (error_code IS NULL OR char_length(error_code) <= 60)
             AND jsonb_typeof(citations) = 'array'
             AND jsonb_typeof(steps) = 'array'
             AND rounds BETWEEN 0 AND 20
             """
           )

    execute("""
    CREATE TRIGGER data_questions_apply_tenant_context
    BEFORE INSERT OR UPDATE ON data_questions
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY data_questions_tenant_policy ON data_questions
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE data_questions ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE data_questions FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:data_questions)

    alter table(:organization_ai_settings) do
      remove :data_questions_enabled
    end
  end
end
