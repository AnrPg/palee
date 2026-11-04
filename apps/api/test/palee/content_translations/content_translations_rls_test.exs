defmodule Palee.ContentTranslations.RLSTest do
  @moduledoc "ADR-520: a box's translations are invisible outside its session."
  use Palee.RLSCase, async: false

  defp org!(conn) do
    {id_s, id} = uuid()

    Postgrex.query!(
      conn,
      "INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at) VALUES ($1, 'Translations RLS', $2, 'active', now(), now())",
      [id, "tr-rls-#{System.unique_integer([:positive])}"]
    )

    {id_s, id}
  end

  test "rows stay in their box", %{conn: conn} do
    {org_s, org} = org!(conn)
    {other_s, _other} = org!(conn)
    {_subject_s, subject} = uuid()
    hash = String.duplicate("a", 64)

    insert = fn organization ->
      Postgrex.query!(
        conn,
        "INSERT INTO content_translations (id, organization_id, subject_kind, subject_id, field, locale, text, source_hash, origin, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, 'package', $2, 'name', 'en', 'Unlimited', $3, 'machine', now(), now())",
        [organization, subject, hash]
      )
    end

    as_session(conn, nil, org_s, false, fn -> insert.(org) end)

    count = fn ->
      %{rows: [[n]]} = Postgrex.query!(conn, "SELECT count(*) FROM content_translations", [])
      n
    end

    assert as_session(conn, nil, org_s, false, count) == 1
    assert as_session(conn, nil, other_s, false, count) == 0
    assert as_session(conn, nil, nil, false, count) == 0

    # A person's text must be checked; a machine's may wait.
    assert_raise Postgrex.Error, ~r/content_translations_check/, fn ->
      as_session(conn, nil, org_s, false, fn ->
        Postgrex.query!(
          conn,
          "UPDATE content_translations SET origin = 'manual', reviewed_at = NULL",
          []
        )
      end)
    end
  end
end
