defmodule Palee.Repo.Migrations.HidePurchaseStarters do
  @moduledoc """
  ADR-642 (revised, ANR 2026-11-13): someone who only started buying a
  package (opened the buy dialog, «Συνέχεια») has no role anyone sees. They
  are not a guest («Επισκέπτης» is someone who really uses the box), not a
  member, and the box's staff do not see them anywhere until they send
  «Το θέλω» or pay.

  Their row (`roles` `{guest}` with `purchase_admission_at` set) only lets
  the box's checkout and «Το θέλω» work for them. The staff lookups now leave
  such rows out:

    * `palee_organization_user_ids/2` (member lists, search, counts, "is
      this person in the box" checks);
    * `palee_organization_member_roles/3` (role facts per member);
    * `palee_add_box_guest/2`: front desk making such a person a guest of
      the box makes them a real guest (the mark goes), so they show.

  Rows the ADR-642 carry-over moved are already marked, so they are hidden
  too; no data changes.
  """

  use Ecto.Migration

  @starter "(om.purchase_admission_at IS NOT NULL AND om.roles::text[] = ARRAY['guest'])"

  def up do
    execute(user_ids_sql("AND NOT #{@starter}"))
    execute(member_roles_sql("AND NOT #{@starter}"))
    execute(add_guest_sql(true))
  end

  def down do
    execute(user_ids_sql(""))
    execute(member_roles_sql(""))
    execute(add_guest_sql(false))
  end

  defp acting_check do
    """
        AND (
          NULLIF(current_setting('app.organization_id', true), '')::uuid = org_id
          OR EXISTS (
            SELECT 1 FROM public.organization_memberships acting
            WHERE acting.organization_id = org_id
              AND acting.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
              AND acting.status = 'active'
          )
          OR EXISTS (
            SELECT 1 FROM public.vendors v
            WHERE v.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
              AND v.status = 'active'
          )
        )
    """
  end

  defp user_ids_sql(hide) do
    """
    CREATE OR REPLACE FUNCTION palee_organization_user_ids(org_id uuid, member_roles text[])
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT om.user_id
      FROM public.organization_memberships om
      WHERE om.organization_id = org_id
        AND om.status = 'active'
        AND (member_roles IS NULL OR om.roles::text[] && member_roles)
        #{hide}
    #{acting_check()}
    $$
    """
  end

  defp member_roles_sql(hide) do
    """
    CREATE OR REPLACE FUNCTION palee_organization_member_roles(
      org_id uuid,
      member_roles text[],
      member_user_id uuid
    )
    RETURNS TABLE (
      user_id uuid,
      role text,
      roles text[],
      coach_scope text,
      notes_visible_to_admins boolean,
      home_location_id uuid
    )
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT om.user_id, om.role::text, om.roles::text[], om.coach_scope::text,
             om.notes_visible_to_admins, om.home_location_id
      FROM public.organization_memberships om
      WHERE om.organization_id = org_id
        AND om.status = 'active'
        AND (member_roles IS NULL OR om.roles::text[] && member_roles)
        AND (member_user_id IS NULL OR om.user_id = member_user_id)
        #{hide}
    #{acting_check()}
    $$
    """
  end

  defp add_guest_sql(reveal?) do
    reveal =
      if reveal?,
        do: """
              IF FOUND AND existing.status = 'active'
                 AND existing.purchase_admission_at IS NOT NULL
                 AND existing.roles::text[] = ARRAY['guest'] THEN
                UPDATE public.organization_memberships
                   SET purchase_admission_at = NULL, invited_by_user_id = actor, updated_at = now()
                 WHERE id = existing.id;
                RETURN existing.id;
              END IF;
        """,
        else: ""

    """
    CREATE OR REPLACE FUNCTION palee_add_box_guest(org_id uuid, guest_user_id uuid)
    RETURNS uuid
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      actor uuid := NULLIF(current_setting('app.user_id', true), '')::uuid;
      existing public.organization_memberships%ROWTYPE;
      new_id uuid;
    BEGIN
      IF actor IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = actor
          AND om.status = 'active'
          AND om.roles && ARRAY['owner', 'admin', 'coach', 'front_desk']::varchar[]
      ) THEN
        RAISE EXCEPTION 'palee_add_box_guest: not allowed' USING ERRCODE = '42501';
      END IF;

      SELECT * INTO existing FROM public.organization_memberships
       WHERE organization_id = org_id AND user_id = guest_user_id
       FOR UPDATE;

    #{reveal}
      IF FOUND AND existing.status = 'active' THEN
        RETURN existing.id;
      ELSIF FOUND THEN
        UPDATE public.organization_memberships
           SET role = 'guest', roles = ARRAY['guest']::varchar[], status = 'active',
               coach_scope = 'own', invited_by_user_id = actor, updated_at = now()
         WHERE id = existing.id;
        RETURN existing.id;
      END IF;

      INSERT INTO public.organization_memberships
        (id, organization_id, user_id, role, roles, status, joined_at, invited_by_user_id,
         inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), org_id, guest_user_id, 'guest', ARRAY['guest']::varchar[], 'active',
         now(), actor, now(), now())
      RETURNING id INTO new_id;

      RETURN new_id;
    END;
    $$
    """
  end
end
