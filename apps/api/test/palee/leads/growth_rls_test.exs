defmodule Palee.Leads.GrowthRLSTest do
  @moduledoc """
  ADR-344/346/347: leads, their events, the box's recipes and the outbox
  are box data under forced RLS. Proves under the runtime role that a row
  written in one box's session is invisible from another box and from no
  box, and that a row written in a box's session always belongs to it.
  """
  use Palee.RLSCase, async: false

  test "leads, lead events, recipes, deliveries and risk actions stay inside their box", %{
    conn: conn
  } do
    {org_s, org} = uuid()
    {other_s, other} = uuid()

    for {id, name} <- [{org, "RLS Growth"}, {other, "RLS Growth Other"}] do
      Postgrex.query!(
        conn,
        """
        INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
        VALUES ($1, $2, $3, 'active', now(), now())
        """,
        [id, name, "rls-growth-#{System.unique_integer([:positive])}"]
      )
    end

    {lead_s, lead} = uuid()
    {_member_s, member} = uuid()
    nick = "rls_growth_#{System.unique_integer([:positive])}"

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
      [member, nick]
    )

    as_session(conn, nil, org_s, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO leads (id, organization_id, name, email, stage, source, stage_changed_at, inserted_at, updated_at)
        VALUES ($1, $2, 'Ελένη', 'eleni@example.com', 'new', 'manual', now(), now(), now())
        """,
        [lead, org]
      )

      Postgrex.query!(
        conn,
        """
        INSERT INTO lead_events (id, organization_id, lead_id, kind, at, inserted_at)
        VALUES (gen_random_uuid(), $1, $2, 'created', now(), now())
        """,
        [org, lead]
      )

      Postgrex.query!(
        conn,
        """
        INSERT INTO box_automations (id, organization_id, recipe, enabled, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, 'welcome', true, now(), now())
        """,
        [org]
      )

      Postgrex.query!(
        conn,
        """
        INSERT INTO automation_deliveries (id, organization_id, recipe, lead_id, trigger_ref, due_at, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, 'trial_follow_up', $2, 'rls', now(), now(), now())
        """,
        [org, lead]
      )

      # ADR-384: the staff action log of members at risk.
      Postgrex.query!(
        conn,
        """
        INSERT INTO retention_risk_actions (id, organization_id, user_id, kind, at, inserted_at)
        VALUES (gen_random_uuid(), $1, $2, 'contacted', now(), now())
        """,
        [org, member]
      )
    end)

    counts = fn session ->
      as_session(conn, nil, session, false, fn ->
        for table <-
              ~w(leads lead_events box_automations automation_deliveries retention_risk_actions) do
          %{rows: [[count]]} = Postgrex.query!(conn, "SELECT count(*) FROM #{table}", [])
          count
        end
      end)
    end

    assert counts.(org_s) == [1, 1, 1, 1, 1]
    assert counts.(other_s) == [0, 0, 0, 0, 0]
    assert counts.(nil) == [0, 0, 0, 0, 0]

    as_session(conn, nil, other_s, false, fn ->
      assert %{num_rows: 0} =
               Postgrex.query!(conn, "UPDATE leads SET stage = 'lost' WHERE id = $1", [lead])

      # The tenant trigger stamps the session's box on the row, whatever
      # box the statement named.
      %{rows: [[stamped]]} =
        Postgrex.query!(
          conn,
          """
          INSERT INTO leads (id, organization_id, name, phone, stage, source, stage_changed_at, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, 'X', '+306940000000', 'new', 'manual', now(), now(), now())
          RETURNING organization_id
          """,
          [org]
        )

      assert stamped == other
    end)

    assert lead_s ==
             as_session(conn, nil, org_s, false, fn ->
               %{rows: [[id]]} = Postgrex.query!(conn, "SELECT id FROM leads", [])
               Ecto.UUID.load!(id)
             end)

    Postgrex.query!(conn, "DELETE FROM organizations WHERE id = ANY($1)", [[org, other]])
    Postgrex.query!(conn, "DELETE FROM users WHERE id = $1", [member])
  end
end
