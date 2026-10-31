defmodule Palee.Repo.Migrations.CreateBoxDataExports do
  @moduledoc """
  ADR-365 (CP-G5): the box's own copy of its data, asked for by an owner at
  any time. One row per request: who asked, its state, and the ZIP of CSV
  files once it is ready (`file`: name, key, bytes, sha256), offered until
  `expires_at`. At most one export in progress per box.
  """

  use Ecto.Migration

  def up do
    create table(:box_data_exports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :requested_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :status, :text, null: false, default: "pending"
      add :record_count, :integer
      add :table_count, :integer
      add :file, :map
      add :error, :text
      add :requested_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:box_data_exports, [:organization_id, :requested_at])

    create unique_index(:box_data_exports, [:organization_id],
             where: "status = 'pending'",
             name: :box_data_exports_one_pending_index
           )

    create constraint(:box_data_exports, :box_data_exports_check,
             check: """
             status IN ('pending', 'ready', 'failed')
             AND (error IS NULL OR char_length(error) <= 500)
             AND (status <> 'ready' OR (file IS NOT NULL AND expires_at IS NOT NULL))
             """
           )

    execute("""
    CREATE TRIGGER box_data_exports_apply_tenant_context
    BEFORE INSERT OR UPDATE ON box_data_exports
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY box_data_exports_tenant_policy ON box_data_exports
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE box_data_exports ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE box_data_exports FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:box_data_exports)
  end
end
