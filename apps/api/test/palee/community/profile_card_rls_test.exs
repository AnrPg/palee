defmodule Palee.Community.ProfileCardRLSTest do
  @moduledoc """
  ADR-554 under real RLS: everyone signed in reads a profile card, only its
  owner writes it, and a person's badges reach an active follower only while
  the owner shows the «Διακρίσεις» tab.
  """

  use Palee.RLSCase, async: false

  setup %{conn: conn} do
    unique = System.unique_integer([:positive])
    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', 'true', false)", [])

    people =
      for name <- [:owner, :follower, :stranger], into: %{} do
        {id_s, id} = uuid()
        nick = "rls_card_#{name}_#{unique}"

        Postgrex.query!(
          conn,
          """
          WITH login AS (
            INSERT INTO logins (id, email, password_hash, inserted_at, updated_at)
            VALUES (gen_random_uuid(), $2::text || '@placeholder.invalid', 'x', now(), now())
            RETURNING id
          )
          INSERT INTO users (id, nickname, display_nickname, role, login_id, inserted_at, updated_at)
          SELECT $1, $2::text, $2::text, 'member', login.id, now(), now() FROM login
          """,
          [id, nick]
        )

        {name, {id_s, id}}
      end

    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', '', false)", [])
    %{people: people}
  end

  test "badges reach active followers only while the owner shows the tab", %{
    conn: conn,
    people: people
  } do
    {owner_s, owner} = people.owner
    {follower_s, follower} = people.follower
    {stranger_s, _stranger} = people.stranger

    as_session(conn, owner_s, nil, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO user_achievements (id, user_id, badge_key, earned_at)
        VALUES (gen_random_uuid(), $1, 'workouts_10', now())
        """,
        [owner]
      )

      Postgrex.query!(
        conn,
        """
        INSERT INTO community_profile_cards (user_id, bio, tabs, inserted_at, updated_at)
        VALUES ($1, 'Olympic lifting', ARRAY['badges'], now(), now())
        """,
        [owner]
      )
    end)

    # The account is public, so the follow is active at once.
    as_session(conn, follower_s, nil, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO community_follows (id, user_id, target_type, target_id, status, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, 'user', $2, 'active', now(), now())
        """,
        [follower, owner]
      )

      assert badge_count(conn, owner) == 1
    end)

    as_session(conn, stranger_s, nil, false, fn ->
      assert badge_count(conn, owner) == 0
      # The card itself is display data: anyone signed in reads it…
      assert %{rows: [["Olympic lifting"]]} =
               Postgrex.query!(
                 conn,
                 "SELECT bio FROM community_profile_cards WHERE user_id = $1",
                 [owner]
               )

      # …but only its owner changes it.
      assert %{num_rows: 0} =
               Postgrex.query!(
                 conn,
                 "UPDATE community_profile_cards SET bio = 'x' WHERE user_id = $1",
                 [owner]
               )
    end)

    as_session(conn, owner_s, nil, false, fn ->
      Postgrex.query!(conn, "UPDATE community_profile_cards SET tabs = '{}' WHERE user_id = $1", [
        owner
      ])
    end)

    as_session(conn, follower_s, nil, false, fn ->
      assert badge_count(conn, owner) == 0
    end)
  end

  test "a session without a person reads no cards", %{conn: conn, people: people} do
    {owner_s, owner} = people.owner

    as_session(conn, owner_s, nil, false, fn ->
      Postgrex.query!(
        conn,
        "INSERT INTO community_profile_cards (user_id, tabs, inserted_at, updated_at) VALUES ($1, '{}', now(), now())",
        [owner]
      )
    end)

    as_session(conn, "", nil, false, fn ->
      assert %{rows: [[0]]} =
               Postgrex.query!(
                 conn,
                 "SELECT count(*)::int FROM community_profile_cards WHERE user_id = $1",
                 [owner]
               )
    end)
  end

  defp badge_count(conn, owner) do
    %{rows: [[count]]} =
      Postgrex.query!(conn, "SELECT count(*)::int FROM user_achievements WHERE user_id = $1", [
        owner
      ])

    count
  end
end
