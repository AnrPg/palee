defmodule Palee.Repo.Migrations.ActivityLog do
  @moduledoc """
  ADR-760: the box's «Αρχείο ενεργειών», one row per change staff made.

    * `activity_log_entries`: what was done (`action`, a key of
      `ActivityLog.Domain.Actions`, and its `area`), by whom (`actor_user_id`,
      their `actor_roles` then; none for the system), when (`occurred_at`),
      about whom (`person_user_id`), on what (`subject`: the ids the request
      named, `subject_label`), what changed (`details`), why (`reason`) and
      whether the member sees it (`reason_shared`). `sensitive` rows go to
      the owner's daily summary. `source_ref` names the row an entry was
      copied from (11A), so copying twice adds nothing.
    * Rows are insert-only (8A). The one update allowed is forgetting a
      person (9A): `reason` to NULL, `details` to `{}` and `redacted_at` set,
      every other column unchanged. They go only with their organization or
      the tenant purge.
    * `activity_log_backfills`: which version of the copy of older records
      (`ActivityLog.Backfill`) a box already has.

  No foreign key to the people: the lineage survives an account being
  deleted; `palee_forget_activity_person(uuid)` forgets a deleted account's
  reasons in every box (9A). The functions pin only `search_path`.
  """

  use Ecto.Migration

  def up do
    create table(:activity_log_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :occurred_at, :utc_datetime_usec, null: false, default: fragment("now()")
      add :action, :string, null: false
      add :area, :string, null: false
      add :actor_user_id, :binary_id
      add :actor_roles, {:array, :string}, null: false, default: []
      add :person_user_id, :binary_id
      add :subject, :map, null: false, default: %{}
      add :subject_label, :text
      add :details, :map, null: false, default: %{}
      add :reason, :text
      add :reason_shared, :boolean, null: false, default: false
      add :sensitive, :boolean, null: false, default: false
      add :request_id, :string
      add :source, :string, null: false, default: "request"
      add :source_ref, :string
      add :redacted_at, :utc_datetime_usec
    end

    create constraint(:activity_log_entries, :activity_log_entries_reason_check,
             check: "reason IS NULL OR char_length(reason) <= 1000"
           )

    create constraint(:activity_log_entries, :activity_log_entries_source_check,
             check: "source IN ('request', 'backfill', 'system')"
           )

    create constraint(:activity_log_entries, :activity_log_entries_actor_check,
             check: "actor_user_id IS NOT NULL OR source <> 'request'"
           )

    create index(:activity_log_entries, [:organization_id, "occurred_at DESC", "id DESC"],
             name: :activity_log_entries_timeline_index
           )

    create index(
             :activity_log_entries,
             [:organization_id, :person_user_id, "occurred_at DESC"],
             name: :activity_log_entries_person_index,
             where: "person_user_id IS NOT NULL"
           )

    create index(:activity_log_entries, [:organization_id, :area, "occurred_at DESC"],
             name: :activity_log_entries_area_index
           )

    create index(:activity_log_entries, [:organization_id, :occurred_at],
             name: :activity_log_entries_sensitive_index,
             where: "sensitive"
           )

    create unique_index(:activity_log_entries, [:organization_id, :source_ref],
             name: :activity_log_entries_source_ref_index,
             where: "source_ref IS NOT NULL"
           )

    execute("""
    CREATE OR REPLACE FUNCTION palee_activity_log_insert_only() RETURNS trigger AS $$
    BEGIN
      IF OLD.redacted_at IS NULL
         AND NEW.redacted_at IS NOT NULL
         AND NEW.reason IS NULL
         AND NEW.details = '{}'::jsonb
         AND NEW.id = OLD.id
         AND NEW.organization_id = OLD.organization_id
         AND NEW.occurred_at = OLD.occurred_at
         AND NEW.action = OLD.action
         AND NEW.area = OLD.area
         AND NEW.actor_user_id IS NOT DISTINCT FROM OLD.actor_user_id
         AND NEW.actor_roles = OLD.actor_roles
         AND NEW.person_user_id IS NOT DISTINCT FROM OLD.person_user_id
         AND NEW.subject = OLD.subject
         AND NEW.subject_label IS NOT DISTINCT FROM OLD.subject_label
         AND NEW.reason_shared = OLD.reason_shared
         AND NEW.sensitive = OLD.sensitive
         AND NEW.request_id IS NOT DISTINCT FROM OLD.request_id
         AND NEW.source = OLD.source
         AND NEW.source_ref IS NOT DISTINCT FROM OLD.source_ref
      THEN
        RETURN NEW;
      END IF;

      RAISE EXCEPTION 'activity_log_entries is insert-only (ADR-760)'
        USING ERRCODE = 'insufficient_privilege';
    END;
    $$ LANGUAGE plpgsql SET search_path = pg_catalog, public
    """)

    execute("""
    CREATE TRIGGER activity_log_entries_insert_only
    BEFORE UPDATE ON activity_log_entries
    FOR EACH ROW EXECUTE FUNCTION palee_activity_log_insert_only()
    """)

    # 9A: a deleted account's rows keep what was done and by whom, without
    # the reason or the details (they may describe the person). Account
    # deletion runs outside any box's session, so through this function, and
    # only for a profile whose deletion is scheduled (as ADR-395's).
    execute("""
    CREATE FUNCTION palee_forget_activity_person(person uuid)
    RETURNS integer
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      changed integer;
    BEGIN
      UPDATE public.activity_log_entries
         SET reason = NULL, details = '{}'::jsonb, redacted_at = now()
       WHERE person_user_id = person
         AND redacted_at IS NULL
         AND EXISTS (
           SELECT 1
           FROM public.account_deletions d
           JOIN public.users u ON u.login_id = d.login_id
           WHERE u.id = person
             AND d.status = 'scheduled'
             AND (d.scope = 'login' OR d.user_id = person)
         );
      GET DIAGNOSTICS changed = ROW_COUNT;
      RETURN changed;
    END
    $$
    """)

    create table(:activity_log_backfills, primary_key: false) do
      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :version, :integer, null: false
      add :entries, :integer, null: false, default: 0
      add :done_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    for table <- ["activity_log_entries", "activity_log_backfills"] do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """)

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  def down do
    drop table(:activity_log_backfills)
    drop table(:activity_log_entries)
    execute("DROP FUNCTION IF EXISTS palee_forget_activity_person(uuid)")
    execute("DROP FUNCTION IF EXISTS palee_activity_log_insert_only()")
  end
end
