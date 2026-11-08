defmodule Palee.Repo.Migrations.ProfileCards do
  @moduledoc """
  ADR-554 (Εγώ as the profile): what a person's profile shows besides name
  and avatar. `bio` is «Λίγα λόγια»; `tabs` are the optional tabs the owner
  added («+ Καρτέλα»), in their order, after the fixed «Πολυμέσα ·
  Αναρτήσεις». Like a name, the card is readable by every signed-in session
  (what each tab holds keeps its own audience rules); only its owner writes.

  `user_achievements_profile_read_policy` lets an active follower read the
  owner's badges, only while the owner shows the «Διακρίσεις» tab.
  """

  use Ecto.Migration

  @owner "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    create table(:community_profile_cards, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :bio, :string, size: 150
      add :tabs, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:community_profile_cards, :community_profile_cards_tabs_check,
             check: "tabs <@ ARRAY['prs', 'badges']::varchar[]"
           )

    execute("ALTER TABLE community_profile_cards ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE community_profile_cards FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE POLICY community_profile_cards_read_policy ON community_profile_cards
    FOR SELECT
    USING (NULLIF(current_setting('app.user_id', true), '') IS NOT NULL)
    """)

    execute("""
    CREATE POLICY community_profile_cards_owner_policy ON community_profile_cards
    FOR ALL USING (#{@owner}) WITH CHECK (#{@owner})
    """)

    execute("""
    CREATE POLICY user_achievements_profile_read_policy ON user_achievements
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1
        FROM public.community_follows f
        WHERE f.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND f.target_type = 'user'
          AND f.target_id = user_achievements.user_id
          AND f.status = 'active'
      )
      AND EXISTS (
        SELECT 1
        FROM public.community_profile_cards c
        WHERE c.user_id = user_achievements.user_id
          AND 'badges' = ANY (c.tabs)
      )
    )
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS user_achievements_profile_read_policy ON user_achievements")
    drop table(:community_profile_cards)
  end
end
