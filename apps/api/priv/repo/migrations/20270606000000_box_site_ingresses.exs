defmodule Palee.Repo.Migrations.BoxSiteIngresses do
  @moduledoc """
  ADR-398: Palee creates the Ingress of a verified custom host itself and
  cert-manager issues its certificate.

    * `box_site_domains` gains the certificate's state as the card shows it
      (`certificate_status`, `certificate_error`, `certificate_checked_at`);
    * `box_site_ingress_ops` is the outbox of cluster calls (apply or delete
      one host's Ingress) with retries; it holds the host, so a delete
      survives the domain row;
    * `palee_site_ingress_hosts()` lists every host that should have an
      Ingress, for the hourly sweep that removes orphans;
    * `palee_box_site_due_organizations` also wakes boxes with due ops.

  Functions pin only `search_path`.
  """

  use Ecto.Migration

  def up do
    alter table(:box_site_domains) do
      add :certificate_status, :string, size: 20, null: false, default: "none"
      add :certificate_error, :string, size: 60
      add :certificate_checked_at, :utc_datetime_usec
    end

    drop constraint(:box_site_domains, :box_site_domains_check)

    create constraint(:box_site_domains, :box_site_domains_check,
             check: """
             status IN ('pending_dns', 'pending_tls', 'active', 'broken', 'expired')
             AND certificate_status IN ('none', 'pending', 'issuing', 'active', 'failed')
             AND attempts >= 0 AND host = lower(host)
             """
           )

    create table(:box_site_ingress_ops, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      # No foreign key: a delete op outlives the domain it removes.
      add :domain_id, :binary_id
      add :host, :string, size: 253, null: false
      add :action, :string, size: 10, null: false
      add :status, :string, size: 10, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec, null: false
      add :claimed_at, :utc_datetime_usec
      add :last_error, :string, size: 60
      timestamps(type: :utc_datetime_usec)
    end

    # One waiting op per host: a newer one replaces it.
    create unique_index(:box_site_ingress_ops, [:host],
             where: "status IN ('pending', 'failed')",
             name: :box_site_ingress_ops_one_waiting_index
           )

    create index(:box_site_ingress_ops, [:organization_id, :status])

    create index(:box_site_ingress_ops, [:next_attempt_at],
             where: "status IN ('pending', 'sending')",
             name: :box_site_ingress_ops_due_index
           )

    create constraint(:box_site_ingress_ops, :box_site_ingress_ops_check,
             check: """
             action IN ('apply', 'delete')
             AND status IN ('pending', 'sending', 'failed')
             AND attempts >= 0 AND host = lower(host)
             """
           )

    execute("""
    CREATE TRIGGER box_site_ingress_ops_apply_tenant_context
    BEFORE INSERT OR UPDATE ON box_site_ingress_ops
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY box_site_ingress_ops_tenant_policy ON box_site_ingress_ops
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE box_site_ingress_ops ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE box_site_ingress_ops FORCE ROW LEVEL SECURITY")

    # The sweep: every host that should have an Ingress, across boxes.
    execute("""
    CREATE FUNCTION palee_site_ingress_hosts()
    RETURNS TABLE (organization_id uuid, host text)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT d.organization_id, d.host::text FROM public.box_site_domains d
      WHERE d.status IN ('pending_tls', 'active', 'broken')
    $$
    """)

    execute(due_organizations(true))
  end

  def down do
    execute(due_organizations(false))
    execute("DROP FUNCTION IF EXISTS palee_site_ingress_hosts()")
    drop table(:box_site_ingress_ops)

    drop constraint(:box_site_domains, :box_site_domains_check)

    create constraint(:box_site_domains, :box_site_domains_check,
             check: """
             status IN ('pending_dns', 'pending_tls', 'active', 'broken', 'expired')
             AND attempts >= 0 AND host = lower(host)
             """
           )

    alter table(:box_site_domains) do
      remove :certificate_status
      remove :certificate_error
      remove :certificate_checked_at
    end
  end

  defp due_organizations(with_ops?) do
    ops =
      if with_ops? do
        """
        UNION
        SELECT o.organization_id FROM public.box_site_ingress_ops o
        WHERE o.status IN ('pending', 'sending') AND o.next_attempt_at <= due_at
        """
      else
        ""
      end

    """
    CREATE OR REPLACE FUNCTION palee_box_site_due_organizations(due_at timestamptz)
    RETURNS TABLE (organization_id uuid)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT d.organization_id FROM public.box_site_domains d
      WHERE d.status IN ('pending_dns', 'pending_tls', 'active', 'broken') AND d.next_check_at <= due_at
      UNION
      SELECT s.organization_id FROM public.box_site_submissions s
      WHERE (s.status IN ('pending', 'sending') AND s.next_attempt_at <= due_at)
         OR (s.conversion_status IN ('pending', 'sending') AND s.conversion_next_at <= due_at)
         OR (s.status = 'failed' AND s.redacted_at IS NULL)
      UNION
      SELECT c.organization_id FROM public.box_site_consents c
      WHERE c.recorded_at < due_at - interval '2 years'
      #{ops}
    $$
    """
  end
end
