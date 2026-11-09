defmodule PaleeWeb.ExerciseMatchesControllerTest do
  @moduledoc """
  ADR-570 over HTTP: the exercises found in a saved free-text draft, links
  skipped, a changed link asked about, the box remembering a «Ναι», and
  edited goals only growing.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Identity, Organizations}

  defp admin(conn) do
    {:ok, user} =
      Identity.register(%{
        nickname: "matches#{System.unique_integer([:positive])}",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, admin} = Identity.update_role(user, :admin)

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Matches Gym #{System.unique_integer([:positive])}"
      })

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {put_bearer_token(conn, admin), organization}
  end

  defp text(text, ref \\ :none) do
    node = %{type: "text", text: text}

    if ref == :none,
      do: node,
      else: Map.put(node, :marks, [%{type: "exerciseLink", attrs: %{ref: ref}}])
  end

  defp draft(conn, org, paragraphs, revision \\ 0, id \\ nil) do
    base = "/api/org/#{org.slug}/admin/workouts"
    id = id || conn |> recycle() |> post(base) |> json_response(201) |> get_in(["draft", "id"])

    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> patch(
      "#{base}/#{id}/draft",
      Jason.encode!(%{
        title: "Friday",
        type: "crossfit",
        authoring_mode: "free_text",
        expected_source_revision: revision,
        free_text_body:
          Enum.map_join(paragraphs, "\n", fn nodes -> Enum.map_join(nodes, & &1.text) end),
        free_text_document: %{
          type: "doc",
          content: Enum.map(paragraphs, &%{type: "paragraph", content: &1})
        },
        sections: []
      })
    )
    |> json_response(200)

    id
  end

  defp matches(conn, org, id),
    do:
      conn
      |> recycle()
      |> get("/api/org/#{org.slug}/admin/workouts/#{id}/exercise-matches")
      |> json_response(200)

  defp decide(conn, org, id, decisions) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post(
      "/api/org/#{org.slug}/admin/workouts/#{id}/exercise-matches/decisions",
      Jason.encode!(%{decisions: decisions})
    )
  end

  test "matches, links, a remembered yes and goals that only grow", %{conn: conn} do
    {conn, org} = admin(conn)

    id =
      draft(conn, org, [
        [text("21-15-9")],
        [text("Thrusters", "thruster")],
        [text("Pulups")],
        [text("Sandbag walk")]
      ])

    assert %{"matches" => [match]} = matches(conn, org, id)

    assert %{
             "typed" => "Pulups",
             "exercise_ref" => "pull-up",
             "line" => 2,
             "from" => 0,
             "to" => 6,
             "remembered" => false
           } = match

    assert %{"id" => "latissimus-dorsi"} = hd(match["muscles"])

    # The coach edited the goals before: only quadriceps as stabilizer.
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put(
      "/api/org/#{org.slug}/admin/workouts/#{id}/goals",
      Jason.encode!(%{
        muscles: [%{id: "quadriceps", role: "stabilizer"}, %{id: "obliques", role: "primary"}],
        qualities: []
      })
    )
    |> json_response(200)

    # The editor saved the answer as a link, then reports it.
    draft(
      conn,
      org,
      [
        [text("21-15-9")],
        [text("Thrusters", "thruster")],
        [text("Pulups", "pull-up")],
        [text("Sandbag walk")]
      ],
      1,
      id
    )

    assert %{"goals_updated" => true} =
             conn
             |> decide(org, id, [%{typed: "Pulups", exercise_ref: "pull-up", decision: "yes"}])
             |> json_response(200)

    goals =
      conn
      |> recycle()
      |> get("/api/org/#{org.slug}/admin/workouts/#{id}/goals")
      |> json_response(200)

    muscles = goals["goals"]["muscles"]
    assert %{"id" => "quadriceps", "role" => "primary"} in muscles
    assert %{"id" => "obliques", "role" => "primary"} in muscles
    assert %{"id" => "latissimus-dorsi", "role" => "primary"} in muscles
    assert goals["goals"]["source"] == "edited"

    # The next workout of the box offers the same words already answered.
    other = draft(conn, org, [[text("pulups"), text(" and run")]])
    assert %{"matches" => found} = matches(conn, org, other)
    assert %{"remembered" => true} = Enum.find(found, &(&1["exercise_ref"] == "pull-up"))
    assert %{"remembered" => false} = Enum.find(found, &(&1["exercise_ref"] == "run"))

    # A «Όχι» to a remembered match forgets it.
    decide(conn, org, other, [%{typed: "pulups", exercise_ref: "pull-up", decision: "no"}])
    |> json_response(200)

    assert %{"matches" => again} = matches(conn, org, other)
    assert %{"remembered" => false} = Enum.find(again, &(&1["exercise_ref"] == "pull-up"))
  end

  test "rejected words are not asked again; a changed link is asked once", %{conn: conn} do
    {conn, org} = admin(conn)

    id =
      draft(conn, org, [
        [text("Run", nil), text(" 400m")],
        [text("run 200m")],
        [text("Push-ups", "pull-up")]
      ])

    assert %{"matches" => [changed]} = matches(conn, org, id)

    assert %{"kind" => "changed", "exercise_ref" => "pull-up", "typed" => "Push-ups", "line" => 2} =
             changed

    assert %{"code" => _} =
             conn
             |> decide(org, id, [%{typed: "x", exercise_ref: "nope", decision: "yes"}])
             |> json_response(422)
  end

  test "another gym cannot read a workout's matches", %{conn: conn} do
    {owner_conn, org} = admin(conn)
    id = draft(owner_conn, org, [[text("Thrusters")]])
    {other_conn, _other} = admin(build_conn())

    assert other_conn
           |> get("/api/org/#{org.slug}/admin/workouts/#{id}/exercise-matches")
           |> json_response(404)
  end
end
