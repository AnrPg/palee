defmodule Palee.BoxSite.RLSTest do
  @moduledoc """
  ADR-352..355: the website and review ask tables are invisible outside
  their box's session, the consent log is insert-only, and the host lookup
  answers across boxes only through its SECURITY DEFINER function.
  """
  use Palee.RLSCase, async: false

  defp org!(conn) do
    {id_s, id} = uuid()

    Postgrex.query!(
      conn,
      "INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at) VALUES ($1, 'Site RLS', $2, 'active', now(), now())",
      [id, "site-rls-#{System.unique_integer([:positive])}"]
    )

    {id_s, id}
  end

  test "rows stay in their box; the consent log cannot be edited", %{conn: conn} do
    {org_s, org} = org!(conn)
    {other_s, other} = org!(conn)
    host = "www.rls#{System.unique_integer([:positive])}.test"
    {visitor_s, visitor} = uuid()

    as_session(conn, nil, org_s, false, fn ->
      Postgrex.query!(
        conn,
        "INSERT INTO box_site_domains (id, organization_id, host, verification_token, status, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, 'tok', 'active', now(), now())",
        [org, host]
      )

      Postgrex.query!(
        conn,
        "INSERT INTO box_site_consents (id, organization_id, visitor_id, banner_version, analytics, marketing, action, recorded_at, expires_at) VALUES (gen_random_uuid(), $1, $2, 1, true, true, 'accept_all', now(), now() + interval '1 day')",
        [org, visitor]
      )

      Postgrex.query!(
        conn,
        "INSERT INTO review_ask_settings (id, organization_id, google_place_id, enabled, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, 'ChIJN1t_tDeuEmsRUsoyG83frY4', true, now(), now())",
        [org]
      )
    end)

    count = fn table ->
      %{rows: [[n]]} = Postgrex.query!(conn, "SELECT count(*) FROM #{table}", [])
      n
    end

    tables = ~w(box_site_domains box_site_consents review_ask_settings)

    assert as_session(conn, nil, org_s, false, fn -> Enum.map(tables, count) end) == [1, 1, 1]
    assert as_session(conn, nil, other_s, false, fn -> Enum.map(tables, count) end) == [0, 0, 0]
    assert as_session(conn, nil, nil, false, fn -> Enum.map(tables, count) end) == [0, 0, 0]

    # Another box cannot write into this box.
    assert_raise Postgrex.Error, fn ->
      as_session(conn, nil, other_s, false, fn ->
        Postgrex.query!(
          conn,
          "INSERT INTO box_site_consents (id, organization_id, visitor_id, banner_version, analytics, marketing, action, recorded_at, expires_at) VALUES (gen_random_uuid(), $1, $2, 1, false, false, 'reject_all', now(), now() + interval '1 day')",
          [org, visitor]
        )
      end)
    end

    assert_raise Postgrex.Error, ~r/insert-only/, fn ->
      as_session(conn, nil, org_s, false, fn ->
        Postgrex.query!(conn, "UPDATE box_site_consents SET marketing = false WHERE visitor_id = $1", [visitor])
      end)
    end

    # The host lookup works with no session, and only names the box.
    assert %{rows: [[_org, _slug, ^host, "active", false]]} =
             as_session(conn, nil, nil, false, fn ->
               Postgrex.query!(conn, "SELECT * FROM palee_site_by_host($1)", [String.upcase(host)])
             end)

    _ = visitor_s
    Postgrex.query!(conn, "DELETE FROM organizations WHERE id = ANY($1)", [[org, other]])
  end
end
