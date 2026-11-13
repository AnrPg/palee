defmodule Palee.Repo.Migrations.PublicCoachBios do
  @moduledoc """
  ADR-641: the public box page shows a coach's «Λίγα λόγια» to visitors
  without an account. `community_profile_cards` is readable only by
  signed-in sessions, so `palee_public_bios(uuid[])` returns the bio of each
  given person whose account is public (`palee_user_is_public`). Private
  accounts never show theirs outside Palee.
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION palee_public_bios(people uuid[])
    RETURNS TABLE (user_id uuid, bio text)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT c.user_id, c.bio
      FROM public.community_profile_cards c
      WHERE c.user_id = ANY(people)
        AND NULLIF(btrim(c.bio), '') IS NOT NULL
        AND palee_user_is_public(c.user_id)
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_public_bios(uuid[])")
  end
end
