defmodule Palee.Repo.Migrations.PublicBoxesProviderKind do
  @moduledoc """
  `palee_public_boxes/1` also answers each business's `provider_kind`
  (`gym` | `coach`), so a list of followed boxes and coaches can say
  «Μέλος box» or «Αθλητής» beside one the person already belongs to
  (ANR 2026-11-13). Same rows as before: an active, live business that
  published its page. A new column changes the return type, so the
  function is dropped and created again.
  """

  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS palee_public_boxes(uuid[])")

    execute("""
    CREATE FUNCTION palee_public_boxes(org_ids uuid[])
     RETURNS TABLE(organization_id uuid, slug text, name text, logo_url text, primary_color text,
                   provider_kind text)
     LANGUAGE sql
     STABLE SECURITY DEFINER
     SET search_path TO 'public', 'pg_temp'
    AS $function$
      SELECT o.id, o.slug::text, COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text,
             s.brand_logo_url::text, s.brand_primary_color::text, o.provider_kind::text
      FROM public.organizations o
      JOIN public.organization_public_profiles p ON p.organization_id = o.id
      LEFT JOIN public.organization_settings s ON s.organization_id = o.id
      WHERE o.id = ANY (org_ids)
        AND o.status = 'active' AND o.activation = 'active'
        AND p.published_at IS NOT NULL
    $function$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_public_boxes(uuid[])")

    execute("""
    CREATE FUNCTION palee_public_boxes(org_ids uuid[])
     RETURNS TABLE(organization_id uuid, slug text, name text, logo_url text, primary_color text)
     LANGUAGE sql
     STABLE SECURITY DEFINER
     SET search_path TO 'public', 'pg_temp'
    AS $function$
      SELECT o.id, o.slug::text, COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text,
             s.brand_logo_url::text, s.brand_primary_color::text
      FROM public.organizations o
      JOIN public.organization_public_profiles p ON p.organization_id = o.id
      LEFT JOIN public.organization_settings s ON s.organization_id = o.id
      WHERE o.id = ANY (org_ids)
        AND o.status = 'active' AND o.activation = 'active'
        AND p.published_at IS NOT NULL
    $function$
    """)
  end
end
