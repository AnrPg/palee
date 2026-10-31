defmodule Palee.Repo.Migrations.BoxSite do
  @moduledoc """
  ADR-352..354: the box's website.

    * `box_site_settings` – one row per box: section order and hidden
      sections, the public timetable switch, FAQ, forms, the box's tag ids
      and the optional Conversions API token (encrypted, `EncryptedBinary`);
    * `box_site_domains` – custom hosts with their DNS proof and TLS state;
      hosts are unique across all boxes;
    * `box_site_submissions` – the form outbox to the leads port (and the
      optional Conversions API event); personal fields are cleared once
      delivered;
    * `box_site_consents` – the insert-only, pseudonymous consent log.

  Public lookups go through SECURITY DEFINER functions that pin only
  `search_path`.
  """

  use Ecto.Migration

  @tables ~w(box_site_settings box_site_domains box_site_submissions box_site_consents)

  def up do
    create table(:box_site_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :section_order, {:array, :string}, null: false, default: []
      add :hidden_sections, {:array, :string}, null: false, default: []
      add :public_schedule, :boolean, null: false, default: false
      add :faq, :map, null: false, default: %{"entries" => []}
      add :forms_enabled, :boolean, null: false, default: true
      add :meta_pixel_id, :string, size: 20
      add :ga4_measurement_id, :string, size: 20
      add :gtm_container_id, :string, size: 20
      add :banner_version, :integer, null: false, default: 1
      add :conversions_api_enabled, :boolean, null: false, default: false
      add :conversions_api_token, :binary
      add :lock_version, :integer, null: false, default: 1
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:box_site_settings, [:organization_id])

    create constraint(:box_site_settings, :box_site_settings_check,
             check: """
             banner_version >= 1
             AND (meta_pixel_id IS NULL OR meta_pixel_id ~ '^[0-9]{5,20}$')
             AND (ga4_measurement_id IS NULL OR ga4_measurement_id ~ '^G-[A-Z0-9]{4,16}$')
             AND (gtm_container_id IS NULL OR gtm_container_id ~ '^GTM-[A-Z0-9]{4,12}$')
             AND (NOT conversions_api_enabled OR (meta_pixel_id IS NOT NULL AND conversions_api_token IS NOT NULL))
             """
           )

    create table(:box_site_domains, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :host, :string, size: 253, null: false
      add :primary, :boolean, null: false, default: false
      add :status, :string, null: false, default: "pending_dns"
      add :verification_token, :string, size: 64, null: false
      add :attempts, :integer, null: false, default: 0
      add :next_check_at, :utc_datetime_usec
      add :checked_at, :utc_datetime_usec
      add :verified_at, :utc_datetime_usec
      add :active_at, :utc_datetime_usec
      add :last_error, :string, size: 60
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:box_site_domains, [:host])
    create index(:box_site_domains, [:organization_id])

    create unique_index(:box_site_domains, [:organization_id],
             where: "\"primary\"",
             name: :box_site_domains_one_primary_index
           )

    create index(:box_site_domains, [:next_check_at],
             where: "status IN ('pending_dns', 'pending_tls', 'active', 'broken')",
             name: :box_site_domains_due_index
           )

    create constraint(:box_site_domains, :box_site_domains_check,
             check: """
             status IN ('pending_dns', 'pending_tls', 'active', 'broken', 'expired')
             AND attempts >= 0 AND host = lower(host)
             """
           )

    create table(:box_site_submissions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :name, :string, size: 80
      add :email, :string, size: 160
      add :phone, :string, size: 32
      add :message, :text
      add :preferred_time, :string, size: 120
      add :class_type_id, :binary_id
      add :locale, :string, size: 10, null: false, default: "el"
      add :marketing_opt_in, :boolean, null: false, default: false
      add :visitor_id, :binary_id
      add :attribution, :map, null: false, default: %{}
      add :consent_text_version, :string, size: 40
      add :consent_text_hash, :string, size: 80
      add :submitted_at, :utc_datetime_usec, null: false
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :claimed_at, :utc_datetime_usec
      add :lead_id, :binary_id
      add :delivered_at, :utc_datetime_usec
      add :last_error, :string, size: 120
      add :redacted_at, :utc_datetime_usec
      add :conversion_status, :string, null: false, default: "none"
      add :conversion_payload, :map
      add :conversion_attempts, :integer, null: false, default: 0
      add :conversion_next_at, :utc_datetime_usec
      add :conversion_claimed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:box_site_submissions, [:organization_id, :status])

    create index(:box_site_submissions, [:next_attempt_at],
             where: "status IN ('pending', 'sending')",
             name: :box_site_submissions_due_index
           )

    create index(:box_site_submissions, [:conversion_next_at],
             where: "conversion_status IN ('pending', 'sending')",
             name: :box_site_submissions_conversion_due_index
           )

    create constraint(:box_site_submissions, :box_site_submissions_check,
             check: """
             kind IN ('trial', 'contact')
             AND status IN ('pending', 'sending', 'delivered', 'failed')
             AND conversion_status IN ('none', 'pending', 'sending', 'sent', 'failed')
             AND attempts >= 0 AND conversion_attempts >= 0
             AND (status <> 'delivered' OR lead_id IS NOT NULL)
             AND (redacted_at IS NOT NULL OR email IS NOT NULL OR phone IS NOT NULL)
             """
           )

    create table(:box_site_consents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :visitor_id, :binary_id, null: false
      add :banner_version, :integer, null: false
      add :analytics, :boolean, null: false
      add :marketing, :boolean, null: false
      add :action, :string, null: false
      add :recorded_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    create index(:box_site_consents, [:organization_id, :visitor_id, :recorded_at])
    create index(:box_site_consents, [:recorded_at])

    create constraint(:box_site_consents, :box_site_consents_check,
             check: """
             action IN ('accept_all', 'reject_all', 'custom', 'withdraw')
             AND banner_version >= 1 AND expires_at > recorded_at
             AND (action <> 'accept_all' OR (analytics AND marketing))
             AND (action NOT IN ('reject_all', 'withdraw') OR (NOT analytics AND NOT marketing))
             """
           )

    # ADR-354: the consent log is evidence; rows are only ever added (and
    # deleted by retention).
    execute("""
    CREATE FUNCTION palee_box_site_consents_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      RAISE EXCEPTION 'box_site_consents rows are insert-only';
    END
    $$
    """)

    execute("""
    CREATE TRIGGER box_site_consents_immutable
    BEFORE UPDATE ON box_site_consents
    FOR EACH ROW EXECUTE FUNCTION palee_box_site_consents_immutable()
    """)

    for table <- @tables do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
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

    # A visitor's host → the box behind it, for an active business only.
    execute("""
    CREATE FUNCTION palee_site_by_host(site_host text)
    RETURNS TABLE (organization_id uuid, slug text, host text, status text, is_primary boolean)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT d.organization_id, o.slug::text, d.host::text, d.status::text, d."primary"
      FROM public.box_site_domains d
      JOIN public.organizations o ON o.id = d.organization_id
      WHERE d.host = lower(site_host) AND o.status = 'active'
      LIMIT 1
    $$
    """)

    # The box's primary active host (canonical URL of its site), if any.
    execute("""
    CREATE FUNCTION palee_site_primary_host(org_id uuid)
    RETURNS text
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT d.host::text FROM public.box_site_domains d
      WHERE d.organization_id = org_id AND d.status = 'active'
      ORDER BY d."primary" DESC, d.active_at ASC
      LIMIT 1
    $$
    """)

    # Ops: hosts in a state (pending_tls: an Ingress is needed).
    execute("""
    CREATE FUNCTION palee_site_domains_for_ops(wanted_status text)
    RETURNS TABLE (host text, slug text, status text, verified_at timestamptz, updated_at timestamptz)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT d.host::text, o.slug::text, d.status::text, d.verified_at, d.updated_at
      FROM public.box_site_domains d
      JOIN public.organizations o ON o.id = d.organization_id
      WHERE d.status = wanted_status
      ORDER BY d.updated_at ASC
      LIMIT 500
    $$
    """)

    # Workers: the boxes with due domain checks or outbox rows.
    execute("""
    CREATE FUNCTION palee_box_site_due_organizations(due_at timestamptz)
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
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_box_site_due_organizations(timestamptz)")
    execute("DROP FUNCTION IF EXISTS palee_site_domains_for_ops(text)")
    execute("DROP FUNCTION IF EXISTS palee_site_primary_host(uuid)")
    execute("DROP FUNCTION IF EXISTS palee_site_by_host(text)")

    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))

    execute("DROP FUNCTION IF EXISTS palee_box_site_consents_immutable()")
  end
end
