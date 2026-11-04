defmodule Palee.Repo.Migrations.FitnessOverridesNeedActiveCoaching do
  @moduledoc """
  ADR-395 (follow-up): a coach's «Τι να δείχνει» choice for a client
  (`fitness_display_overrides`) counts only while the box still coaches the
  client. Once the last active coaching relationship in that box ends, the
  former coach can no longer change or clear it, so it must stop hiding the
  client's account-wide card.

    * `palee_client_coached_in(p_organization)`: a narrow SECURITY DEFINER
      function (ADR-131 §2) that answers only whether the session user has an
      active coaching relationship in that box (the client cannot read
      `coaching_relationships`, which is tenant-scoped). It pins only
      `search_path`.
    * The client's SELECT policy on `fitness_display_overrides` now also
      needs that answer, so a stale override is ignored however the
      relationship ended.
    * Overrides already left without an active relationship are deleted.
    * `palee_forget_fitness_overrides(p_user_id)`: deletes every box's
      override of a profile whose deletion is scheduled (ADR-211), for the
      account-deletion sweep, which runs with no session scope and cannot
      see the boxes' rows. A profile kept anonymised for a business's
      accounts keeps no fitness preferences; without a scheduled deletion of
      that profile the function deletes nothing.
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION palee_client_coached_in(p_organization uuid)
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1
        FROM coaching_relationships r
        WHERE r.organization_id = p_organization
          AND r.client_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND r.ended_at IS NULL
      )
    $$
    """)

    execute("""
    CREATE FUNCTION palee_forget_fitness_overrides(p_user_id uuid)
    RETURNS integer
    LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      WITH gone AS (
        DELETE FROM fitness_display_overrides o
        WHERE o.client_user_id = p_user_id
          AND EXISTS (
            SELECT 1
            FROM account_deletions d
            JOIN users u ON u.login_id = d.login_id
            WHERE u.id = p_user_id
              AND d.status = 'scheduled'
              AND (d.scope = 'login' OR d.user_id = p_user_id)
          )
        RETURNING 1
      )
      SELECT count(*)::integer FROM gone
    $$
    """)

    execute(
      "DROP POLICY fitness_display_overrides_client_read_policy ON fitness_display_overrides"
    )

    execute("""
    CREATE POLICY fitness_display_overrides_client_read_policy ON fitness_display_overrides
    FOR SELECT USING (
      client_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      AND palee_client_coached_in(organization_id)
    )
    """)

    execute("""
    DELETE FROM fitness_display_overrides o
    WHERE NOT EXISTS (
      SELECT 1
      FROM coaching_relationships r
      WHERE r.organization_id = o.organization_id
        AND r.client_user_id = o.client_user_id
        AND r.ended_at IS NULL
    )
    """)
  end

  def down do
    execute(
      "DROP POLICY fitness_display_overrides_client_read_policy ON fitness_display_overrides"
    )

    execute("""
    CREATE POLICY fitness_display_overrides_client_read_policy ON fitness_display_overrides
    FOR SELECT USING (client_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("DROP FUNCTION IF EXISTS palee_forget_fitness_overrides(uuid)")
    execute("DROP FUNCTION IF EXISTS palee_client_coached_in(uuid)")
  end
end
