defmodule PaleeWeb.FollowSuggestionControllerTest do
  @moduledoc """
  ADR-561: «Ίσως γνωρίζεις». Broad suggestions for a new person (their box,
  its coach, the most followed), never people they cannot or should not
  see, ✕ with undo, follows from a suggestion, «Και αυτοί ίσως» and the
  anonymous counters.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  import Palee.AnalyticsHelpers, only: [organization_fixture: 1, add_membership: 3]

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    %{as: fn user -> put_bearer_token(conn, user) end}
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp suggestions(ctx, user, query \\ "") do
    ctx.as.(user)
    |> get("/api/me/follow-suggestions#{query}")
    |> json_response(200)
    |> Map.fetch!("people")
  end

  defp ids(people), do: Enum.map(people, & &1["id"])

  defp follow!(ctx, from, to) do
    ctx.as.(from)
    |> send_json(:post, "/api/me/follows", %{target_type: "user", target_id: to.id})
    |> json_response(200)
  end

  defp counters do
    %{rows: rows} =
      Palee.Repo.query!(
        "SELECT reason, event, sum(count)::int FROM community_follow_suggestion_events GROUP BY 1, 2"
      )

    Map.new(rows, fn [reason, event, n] -> {{reason, event}, n} end)
  end

  test "a new box member is offered the box's people, the coach shown as coach", ctx do
    {box, owner, _context} = organization_fixture(nil)
    me = add_membership(box, user_fixture(), :member)
    mate = add_membership(box, user_fixture(), :member)
    coach = add_membership(box, user_fixture(), :coach)
    private_mate = add_membership(box, private_account!(user_fixture()), :member)
    private_stranger = private_account!(user_fixture())

    people = suggestions(ctx, me)
    by_id = Map.new(people, &{&1["id"], &1})

    assert by_id[mate.id]["reason"]["kind"] == "box"
    assert by_id[mate.id]["reason"]["box"]["name"] == box.name
    assert by_id[coach.id]["reason"]["kind"] == "coach"
    assert by_id[owner.id]["reason"]["kind"] == "coach"
    assert by_id[private_mate.id]["private"]
    refute Map.has_key?(by_id, me.id)
    refute Map.has_key?(by_id, private_stranger.id)

    # Counted anonymously per reason shown.
    assert counters()[{"box", "shown"}] >= 2
    assert counters()[{"coach", "shown"}] >= 2
  end

  test "someone who follows you comes first; blocked and hidden people never show", ctx do
    me = user_fixture()
    fan = user_fixture()
    blocked = user_fixture()
    hidden = user_fixture()

    for person <- [blocked, hidden], do: follow!(ctx, person, me)
    follow!(ctx, fan, me)

    ctx.as.(me) |> send_json(:post, "/api/me/blocks", %{user_id: blocked.id})

    ctx.as.(hidden)
    |> send_json(:put, "/api/me/social/privacy", %{private_account: false, searchable: false})

    people = suggestions(ctx, me)
    assert [%{"reason" => %{"kind" => "follows_you"}} = first | _] = people
    assert first["id"] == fan.id
    refute blocked.id in ids(people)
    refute hidden.id in ids(people)
  end

  test "a new person with nothing to go on still gets the most followed people", ctx do
    me = user_fixture()
    star = user_fixture()
    for _ <- 1..3, do: follow!(ctx, user_fixture(), star)

    assert star.id in ids(suggestions(ctx, me))
  end

  test "✕ hides a person until they follow you; undo brings them back", ctx do
    {box, _owner, _context} = organization_fixture(nil)
    me = add_membership(box, user_fixture(), :member)
    mate = add_membership(box, user_fixture(), :member)

    assert mate.id in ids(suggestions(ctx, me))

    assert ctx.as.(me)
           |> send_json(:post, "/api/me/follow-suggestions/#{mate.id}/dismiss", %{reason: "box"})
           |> response(204)

    refute mate.id in ids(suggestions(ctx, me))
    assert counters()[{"box", "dismissed"}] == 1

    assert ctx.as.(me) |> delete("/api/me/follow-suggestions/#{mate.id}/dismiss") |> response(204)
    assert mate.id in ids(suggestions(ctx, me))

    ctx.as.(me)
    |> send_json(:post, "/api/me/follow-suggestions/#{mate.id}/dismiss", %{reason: "box"})

    follow!(ctx, mate, me)
    assert [%{"reason" => %{"kind" => "follows_you"}} = back | _] = suggestions(ctx, me)
    assert back["id"] == mate.id
  end

  test "following from a suggestion follows, counts and drops the person", ctx do
    {box, _owner, _context} = organization_fixture(nil)
    me = add_membership(box, user_fixture(), :member)
    mate = add_membership(box, user_fixture(), :member)

    assert %{"status" => "active"} =
             ctx.as.(me)
             |> send_json(:post, "/api/me/follow-suggestions/#{mate.id}/follow", %{reason: "box"})
             |> json_response(200)

    refute mate.id in ids(suggestions(ctx, me))
    assert counters()[{"box", "followed"}] == 1

    assert ctx.as.(me)
           |> send_json(:post, "/api/me/follow-suggestions/#{mate.id}/follow", %{reason: "nope"})
           |> json_response(422)
  end

  test "«Και αυτοί ίσως» names the people a public person follows, with common follows", ctx do
    me = user_fixture()
    seed = user_fixture()
    their_friend = user_fixture()
    follow!(ctx, me, seed)
    follow!(ctx, seed, their_friend)

    people = suggestions(ctx, me, "?seed=#{seed.id}&limit=5")
    found = Enum.find(people, &(&1["id"] == their_friend.id))
    assert found["reason"]["kind"] in ["via_person", "mutual"]
    assert found["reason"]["mutual_count"] == 1
    assert [%{"id" => seed_id}] = found["reason"]["mutuals"]
    assert seed_id == seed.id

    # A private seed's follows stay hidden from people who do not follow them.
    stranger = user_fixture()
    private_account!(seed)
    # (They may still show as a popular person, never through the seed.)
    refute Enum.any?(
             suggestions(ctx, stranger, "?seed=#{seed.id}"),
             &(&1["reason"]["kind"] == "via_person")
           )
  end

  test "«Κρύψε τις προτάσεις» is remembered and comes back from the settings", ctx do
    me = user_fixture()
    privacy = fn -> json_response(get(ctx.as.(me), "/api/me/social"), 200)["privacy"] end
    assert privacy.()["show_follow_suggestions"]

    assert ctx.as.(me)
           |> send_json(:put, "/api/me/social/privacy", %{show_follow_suggestions: false})
           |> json_response(200)
           |> Map.fetch!("show_follow_suggestions") == false

    refute privacy.()["show_follow_suggestions"]
    assert privacy.()["private_account"] == false

    ctx.as.(me) |> send_json(:put, "/api/me/social/privacy", %{show_follow_suggestions: true})
    assert privacy.()["show_follow_suggestions"]
  end

  test "limit is bounded", ctx do
    me = user_fixture()
    assert ctx.as.(me) |> get("/api/me/follow-suggestions?limit=0") |> json_response(422)
    assert ctx.as.(me) |> get("/api/me/follow-suggestions?limit=51") |> json_response(422)
  end
end
