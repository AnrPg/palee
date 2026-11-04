defmodule Palee.Repo.Migrations.BoxSiteHostNotAllowed do
  @moduledoc """
  ADR-398 (2026-11-03): `palee_site_ingress_hosts()` for the nightly sweep.

    * A host the cluster's tenant policy refuses
      (`certificate_error = 'host_not_allowed'`) is final, so the sweep must
      not recreate its Ingress: it is left out.
    * The rows carry the domain's id and `certificate_status`, so the sweep
      can reread active certificates once a night (the 5-minute checks read
      only certificates still being issued).

  Functions pin only `search_path`.
  """

  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS palee_site_ingress_hosts()")

    execute("""
    CREATE FUNCTION palee_site_ingress_hosts()
    RETURNS TABLE (organization_id uuid, id uuid, host text, certificate_status text)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT d.organization_id, d.id, d.host::text, d.certificate_status::text
      FROM public.box_site_domains d
      WHERE d.status IN ('pending_tls', 'active', 'broken')
        AND d.certificate_error IS DISTINCT FROM 'host_not_allowed'
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_site_ingress_hosts()")

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
  end
end
