defmodule Palee.Repo.Migrations.BoxFollowerInvites do
  @moduledoc """
  ADR-580: a box invites the people who follow it to become box members,
  one at a time or many at once.

  * `organization_follower_invites`: one row per invitation sent. The box
    (tenant scope) writes and reads its own; the invited person reads theirs
    at any box and answers «Όχι, ευχαριστώ» inside that box's scope. A
    declined invitation stops further ones from that box.
  * `community_social_settings.box_invites`: «Δέχομαι προσκλήσεις από box
    που ακολουθώ», on by default (ANR 2026-11-09). Off keeps the person out
    of every box's list of followers.
  * `palee_box_followers(...)` / `palee_box_follower_counts(...)`: who
    follows the box in scope (`app.organization_id`) and is not a box
    member, with the facts the staff list shows. Follows are personal rows,
    so these SECURITY DEFINER functions return only what the box may see:
    people who accept invitations, never box members (an active membership
    with a role other than guest), never people whose «Ζήτα να γίνεις μέλος»
    is open (they are in the join requests).

  Notification type `follower_invited` (to the person). The constraint is
  rewritten from what the database holds, so types other migrations add are
  kept. Functions pin only `search_path` (never an extension GUC).
  """

  use Ecto.Migration

  @types ~w(follower_invited)
  @box "NULLIF(current_setting('app.organization_id', true), '')::uuid"

  def up do
    create table(:organization_follower_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :message, :text

      add :package_id,
          references(:membership_packages, type: :binary_id, on_delete: :nilify_all)

      add :offer_trial, :boolean, null: false, default: false
      add :status, :string, null: false, default: "sent"
      add :answered_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:organization_follower_invites, :organization_follower_invites_status_check,
             check: "status IN ('sent', 'declined')"
           )

    create constraint(:organization_follower_invites, :organization_follower_invites_answer_check,
             check: "(status = 'sent') = (answered_at IS NULL)"
           )

    create constraint(
             :organization_follower_invites,
             :organization_follower_invites_message_check,
             check: "message IS NULL OR char_length(message) <= 500"
           )

    create index(:organization_follower_invites, [:organization_id, :user_id, :inserted_at])
    create index(:organization_follower_invites, [:user_id, :inserted_at])

    execute("""
    CREATE TRIGGER organization_follower_invites_apply_tenant_context
    BEFORE INSERT OR UPDATE ON organization_follower_invites
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    org = "organization_id = #{@box}"
    me = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY organization_follower_invites_tenant_policy ON organization_follower_invites
    FOR ALL USING (#{org}) WITH CHECK (#{org})
    """)

    execute("""
    CREATE POLICY organization_follower_invites_owner_read_policy ON organization_follower_invites
    FOR SELECT USING (#{me})
    """)

    execute("ALTER TABLE organization_follower_invites ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE organization_follower_invites FORCE ROW LEVEL SECURITY")

    alter table(:community_social_settings) do
      add :box_invites, :boolean, null: false, default: true
    end

    followers_function()
    counts_function()
    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute("DELETE FROM notifications WHERE type = 'follower_invited'")
    rewrite_notification_types(&(&1 -- @types))
    execute("DROP FUNCTION IF EXISTS palee_box_follower_counts(timestamptz)")

    execute(
      "DROP FUNCTION IF EXISTS palee_box_followers(text, integer, timestamptz, uuid, timestamptz, uuid[])"
    )

    alter table(:community_social_settings) do
      remove :box_invites
    end

    drop table(:organization_follower_invites)
  end

  # The box's followers who may be listed, with their facts. `reinvite_before`
  # (an invitation sent before it may be followed by another) comes from
  # FollowerInvitePolicy, so the rule lives in one place.
  defp listed_sql do
    """
    WITH box AS (SELECT #{@box} AS id),
    listed AS (
      SELECT f.user_id, f.inserted_at AS followed_at,
        EXISTS (
          SELECT 1 FROM organization_memberships m
          WHERE m.organization_id = (SELECT id FROM box) AND m.user_id = f.user_id
            AND m.status IN ('suspended', 'revoked')
        ) AS former_member,
        EXISTS (
          SELECT 1 FROM scheduling_trial_requests t
          WHERE t.organization_id = (SELECT id FROM box) AND t.user_id = f.user_id
        ) AS had_trial,
        last.status AS invite_status,
        last.inserted_at AS invited_at
      FROM community_follows f
      LEFT JOIN LATERAL (
        SELECT i.status, i.inserted_at FROM organization_follower_invites i
        WHERE i.organization_id = (SELECT id FROM box) AND i.user_id = f.user_id
        ORDER BY (i.status = 'declined') DESC, i.inserted_at DESC
        LIMIT 1
      ) last ON true
      WHERE (SELECT id FROM box) IS NOT NULL
        AND f.target_type = 'organization' AND f.target_id = (SELECT id FROM box)
        AND f.status = 'active'
        AND COALESCE(
          (SELECT s.box_invites FROM community_social_settings s WHERE s.user_id = f.user_id),
          true
        )
        AND NOT EXISTS (
          SELECT 1 FROM organization_memberships m
          WHERE m.organization_id = (SELECT id FROM box) AND m.user_id = f.user_id
            AND m.status = 'active'
            AND NOT (COALESCE(NULLIF(m.roles::text[], '{}'), ARRAY[m.role::text]) <@ ARRAY['guest']::text[])
        )
        AND NOT EXISTS (
          SELECT 1 FROM organization_join_requests r
          WHERE r.organization_id = (SELECT id FROM box) AND r.user_id = f.user_id
            AND r.status = 'requested'
        )
    )
    """
  end

  defp followers_function do
    execute("""
    CREATE OR REPLACE FUNCTION palee_box_followers(
      kind text, lim integer, before_at timestamptz, before_id uuid, reinvite_before timestamptz,
      among uuid[]
    )
    RETURNS TABLE (user_id uuid, followed_at timestamptz, former_member boolean,
                   had_trial boolean, invite_status text, invited_at timestamptz,
                   invitable boolean)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      #{listed_sql()}
      SELECT l.user_id, l.followed_at, l.former_member, l.had_trial, l.invite_status,
        l.invited_at,
        (l.invite_status IS NULL
          OR (l.invite_status = 'sent' AND l.invited_at <= reinvite_before))
      FROM listed l
      WHERE (kind = 'all' OR (kind = 'trial' AND l.had_trial)
             OR (kind = 'former' AND l.former_member))
        AND (before_at IS NULL OR (l.followed_at, l.user_id) < (before_at, before_id))
        AND (among IS NULL OR l.user_id = ANY (among))
      ORDER BY l.followed_at DESC, l.user_id DESC
      LIMIT lim
    $$
    """)
  end

  defp counts_function do
    execute("""
    CREATE OR REPLACE FUNCTION palee_box_follower_counts(reinvite_before timestamptz)
    RETURNS TABLE (listed bigint, invitable bigint, trial bigint, former bigint)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      #{listed_sql()}
      SELECT count(*),
        count(*) FILTER (WHERE l.invite_status IS NULL
          OR (l.invite_status = 'sent' AND l.invited_at <= reinvite_before)),
        count(*) FILTER (WHERE l.had_trial),
        count(*) FILTER (WHERE l.former_member)
      FROM listed l
    $$
    """)
  end

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
