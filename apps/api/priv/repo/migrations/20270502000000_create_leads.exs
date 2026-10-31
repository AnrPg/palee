defmodule Palee.Repo.Migrations.CreateLeads do
  @moduledoc """
  ADR-344/345: the box's «Ενδιαφερόμενοι». A lead is a person who is not a
  box member yet: they asked on the box's form, came by a join link, were
  typed in by staff or imported from a file. Each lead has a stage
  (new → trial → offer → converted / lost), a source, an owner on the staff,
  open tasks (the next action) and a history (`lead_events`) that stays
  after the lead becomes a box member.

  Consent (ADR-345) is kept as evidence on the lead: when contact and
  marketing consent were given, the version and hash of the text shown.
  """

  use Ecto.Migration

  @tables ~w(leads lead_tasks lead_events)

  def change do
    create table(:leads, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :email, :string
      add :phone, :string
      add :message, :text
      add :locale, :string, size: 8
      add :stage, :string, null: false, default: "new"
      add :source, :string, null: false
      add :source_ref, :string
      add :campaign, :string
      add :interests, {:array, :string}, null: false, default: []
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      # The person's own account once known (a conversion, or a lead who
      # signed up). Deleting the account deletes the lead with its history.
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :lost_reason, :string
      add :stage_changed_at, :utc_datetime_usec, null: false
      add :converted_at, :utc_datetime_usec
      add :last_contacted_at, :utc_datetime_usec
      add :consent_contact_at, :utc_datetime_usec
      add :consent_marketing_at, :utc_datetime_usec
      add :consent_text_version, :string
      add :consent_text_hash, :string
      add :marketing_opted_out_at, :utc_datetime_usec
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:leads, :leads_stage_check,
             check: "stage IN ('new', 'trial', 'offer', 'converted', 'lost')"
           )

    create constraint(:leads, :leads_contact_check,
             check: "email IS NOT NULL OR phone IS NOT NULL"
           )

    create constraint(:leads, :leads_converted_check,
             check: "(stage = 'converted') = (converted_at IS NOT NULL)"
           )

    # One open lead per address: a second enquiry joins the first.
    create unique_index(:leads, [:organization_id, :email],
             name: :leads_one_open_per_email_index,
             where: "email IS NOT NULL AND stage NOT IN ('converted', 'lost')"
           )

    # The same capture retried (a form resubmitted, an assistant retrying).
    create unique_index(:leads, [:organization_id, :source, :source_ref],
             name: :leads_source_ref_index,
             where: "source_ref IS NOT NULL"
           )

    create index(:leads, [:organization_id, :stage, :inserted_at])
    create index(:leads, [:organization_id, :owner_id])
    create index(:leads, [:user_id])
    create index(:leads, [:owner_id])
    create index(:leads, [:created_by_id])

    create table(:lead_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :lead_id, references(:leads, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :due_at, :utc_datetime_usec, null: false
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :done_at, :utc_datetime_usec
      add :done_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:lead_tasks, [:organization_id, :done_at, :due_at])
    create index(:lead_tasks, [:lead_id])
    create index(:lead_tasks, [:assignee_id])
    create index(:lead_tasks, [:done_by_id])
    create index(:lead_tasks, [:created_by_id])

    create table(:lead_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :lead_id, references(:leads, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :data, :map, null: false, default: %{}
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:lead_events, [:lead_id, :at])
    create index(:lead_events, [:organization_id])
    create index(:lead_events, [:actor_id])

    for table <- @tables, do: secure(table)
  end

  defp secure(table) do
    execute(
      """
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """,
      "DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}"
    )

    execute(
      """
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}"
    )

    execute(
      "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY",
      "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
    )
  end
end
