defmodule Palee.AiHelp.RLSEnforcementTest do
  @moduledoc """
  ADR-361..363 under real row-level security (`Palee.RLSCase`): data
  questions and support conversations stay inside their box; support
  tickets are also visible to the Palee team and to nobody else; help
  articles are public once published, and only the Palee team writes them.
  """

  use Palee.RLSCase, async: false

  defp org(conn, label) do
    {id_s, id} = uuid()

    Postgrex.query!(
      conn,
      "INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at) VALUES ($1, $2, $3, 'active', now(), now())",
      [id, "RLS #{label}", "rls-aihelp-#{label}-#{System.unique_integer([:positive])}"]
    )

    {id_s, id}
  end

  defp user(conn, label) do
    {id_s, id} = uuid()

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
      [id, "rls_aihelp_#{label}_#{System.unique_integer([:positive])}"]
    )

    {id_s, id}
  end

  defp ids(conn, sql), do: conn |> Postgrex.query!(sql, []) |> Map.fetch!(:rows) |> List.flatten()

  test "data questions and support conversations are invisible outside their box", %{conn: conn} do
    {org_s, org} = org(conn, "a")
    {other_s, _other} = org(conn, "b")
    {staff_s, staff} = user(conn, "staff")

    as_session(conn, staff_s, org_s, false, fn ->
      Postgrex.query!(
        conn,
        "INSERT INTO data_questions (id, organization_id, user_id, question, locale, status, inserted_at) VALUES (gen_random_uuid(), $1, $2, 'q', 'el', 'answered', now())",
        [org, staff]
      )

      Postgrex.query!(
        conn,
        "INSERT INTO help_desk_conversations (id, organization_id, user_id, status, locale, subject, last_message_at, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 'assistant', 'el', 's', now(), now(), now())",
        [org, staff]
      )
    end)

    assert as_session(conn, staff_s, org_s, false, fn -> ids(conn, "SELECT count(*) FROM data_questions") end) == [1]
    assert as_session(conn, staff_s, other_s, false, fn -> ids(conn, "SELECT count(*) FROM data_questions") end) == [0]
    assert as_session(conn, staff_s, other_s, false, fn -> ids(conn, "SELECT count(*) FROM help_desk_conversations") end) == [0]

    # The tenant trigger stamps the session's box: a row cannot be written into another one.
    as_session(conn, staff_s, other_s, false, fn ->
      Postgrex.query!(
        conn,
        "INSERT INTO data_questions (id, organization_id, user_id, question, locale, status, inserted_at) VALUES (gen_random_uuid(), $1, $2, 'q', 'el', 'answered', now())",
        [org, staff]
      )
    end)

    assert as_session(conn, staff_s, org_s, false, fn -> ids(conn, "SELECT count(*) FROM data_questions") end) == [1]
  end

  test "tickets are seen by their box and by the Palee team, by no other box", %{conn: conn} do
    {org_s, org} = org(conn, "t")
    {other_s, _other} = org(conn, "u")
    {staff_s, staff} = user(conn, "tstaff")
    {vendor_s, vendor} = user(conn, "vendor")

    Postgrex.query!(conn, "SELECT set_config('app.vendor_grant', 'true', false)", [])
    Postgrex.query!(conn, "INSERT INTO vendors (id, user_id, status, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, 'active', now(), now())", [vendor])
    Postgrex.query!(conn, "SELECT set_config('app.vendor_grant', '', false)", [])

    as_session(conn, staff_s, org_s, false, fn ->
      [[conversation]] =
        Postgrex.query!(
          conn,
          "INSERT INTO help_desk_conversations (id, organization_id, user_id, status, locale, subject, last_message_at, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 'waiting_for_palee', 'el', 's', now(), now(), now()) RETURNING id",
          [org, staff]
        ).rows

      Postgrex.query!(
        conn,
        "INSERT INTO help_desk_tickets (id, organization_id, conversation_id, requester_id, summary, locale, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, $3, 'help', 'el', now(), now())",
        [org, conversation, staff]
      )
    end)

    count = "SELECT count(*) FROM help_desk_tickets"
    assert as_session(conn, staff_s, org_s, false, fn -> ids(conn, count) end) == [1]
    assert as_session(conn, staff_s, other_s, false, fn -> ids(conn, count) end) == [0]
    assert as_session(conn, staff_s, nil, false, fn -> ids(conn, count) end) == [0]
    assert as_session(conn, vendor_s, nil, false, fn -> ids(conn, count) end) == [1]
    # The team sees the ticket, not the box's conversation, outside the box's session.
    assert as_session(conn, vendor_s, nil, false, fn -> ids(conn, "SELECT count(*) FROM help_desk_conversations") end) == [0]
  after
    Postgrex.query!(conn, "DELETE FROM vendors WHERE user_id IN (SELECT id FROM users WHERE nickname LIKE 'rls\\_aihelp\\_vendor%')", [])
  end

  test "help articles: published are public, drafts and writes belong to the Palee team", %{conn: conn} do
    {member_s, _member} = user(conn, "reader")
    slug = "rls-article-#{System.unique_integer([:positive])}"

    # The system (no acting person) seeds.
    as_session(conn, "", nil, false, fn ->
      for {suffix, status, published} <- [{"pub", "published", "now()"}, {"draft", "draft", "NULL"}] do
        Postgrex.query!(
          conn,
          "INSERT INTO help_articles (id, slug, locale, title, summary, status, published_at, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, 'en', 't', 's', $2, #{published}, now(), now())",
          ["#{slug}-#{suffix}", status]
        )
      end
    end)

    visible =
      as_session(conn, member_s, nil, false, fn ->
        ids(conn, "SELECT slug FROM help_articles WHERE slug LIKE '#{slug}%' ORDER BY slug")
      end)

    assert visible == ["#{slug}-pub"]

    assert_raise Postgrex.Error, fn ->
      as_session(conn, member_s, nil, false, fn ->
        Postgrex.query!(
          conn,
          "INSERT INTO help_articles (id, slug, locale, title, summary, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, 'en', 't', 's', now(), now())",
          ["#{slug}-mine"]
        )
      end)
    end

    as_session(conn, "", nil, false, fn ->
      Postgrex.query!(conn, "DELETE FROM help_articles WHERE slug LIKE '#{slug}%'", [])
    end)
  end
end
