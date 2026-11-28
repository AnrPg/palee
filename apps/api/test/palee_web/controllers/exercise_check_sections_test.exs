defmodule PaleeWeb.ExerciseCheckSectionsTest do
  @moduledoc """
  ADR-671 over HTTP: a sectioned draft's exercises are checked section by
  section before publishing, and publishing grows goals the coach edited
  with what new exercises bring, never putting back what the coach removed.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Identity, Organizations}

  defp admin(conn) do
    {:ok, user} =
      Identity.register(%{
        nickname: "sections#{System.unique_integer([:positive])}",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, admin} = Identity.update_role(user, :admin)

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Sections Gym #{System.unique_integer([:positive])}"
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

  defp new_draft(conn, org),
    do:
      conn
      |> recycle()
      |> post("/api/org/#{org.slug}/admin/workouts")
      |> json_response(201)
      |> get_in(["draft", "id"])

  # The editor's payload (SectionedWorkoutEditor): each section's text and document.
  defp sectioned(sections) do
    sections =
      sections
      |> Enum.with_index(1)
      |> Enum.map(fn {{name, body}, order} ->
        %{
          name: name,
          order: order,
          exercises: [],
          free_text_body: body,
          free_text_document: %{
            type: "doc",
            content:
              body
              |> String.split("\n")
              |> Enum.map(&%{type: "paragraph", content: [%{type: "text", text: &1}]})
          },
          timer_preset: nil,
          score_config: nil
        }
      end)

    base = %{
      title: "Saturday",
      type: "crossfit",
      authoring_mode: "sectioned_text",
      workout_metadata: %{},
      sections: sections
    }

    Map.put(base, :draft_data, base)
  end

  defp save(conn, org, id, payload, revision) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> patch(
      "/api/org/#{org.slug}/admin/workouts/#{id}/draft",
      Jason.encode!(Map.put(payload, :expected_source_revision, revision))
    )
    |> json_response(200)
  end

  defp goals(conn, org, id),
    do:
      conn
      |> recycle()
      |> get("/api/org/#{org.slug}/admin/workouts/#{id}/goals")
      |> json_response(200)

  test "a sectioned draft's matches name their section and its own line", %{conn: conn} do
    {conn, org} = admin(conn)
    id = new_draft(conn, org)

    save(
      conn,
      org,
      id,
      sectioned([{"Warm-up", "Row 500m"}, {"", "21-15-9\nThrustr\nPull-ups"}]),
      0
    )

    %{"matches" => matches} =
      conn
      |> recycle()
      |> get("/api/org/#{org.slug}/admin/workouts/#{id}/exercise-matches")
      |> json_response(200)

    assert %{"section" => 0, "line" => 0, "id" => "0:0:" <> _} =
             Enum.find(matches, &(&1["exercise_ref"] == "row"))

    assert %{"section" => 1, "line" => 1, "kind" => "fuzzy", "typed" => "Thrustr"} =
             Enum.find(matches, &(&1["exercise_ref"] == "thruster"))

    assert %{"section" => 1, "line" => 2} = Enum.find(matches, &(&1["exercise_ref"] == "pull-up"))
  end

  test "publishing grows edited goals with new exercises only", %{conn: conn} do
    {conn, org} = admin(conn)
    id = new_draft(conn, org)
    save(conn, org, id, sectioned([{"", "Thrusters"}]), 0)

    %{"goals" => suggested} = goals(conn, org, id)
    pull_up = Palee.Anatomy.exercise_targets("pull-up").muscles |> Enum.map(& &1.id)
    removed = Enum.find(suggested["muscles"], &(&1["id"] not in pull_up))
    kept = suggested["muscles"] -- [removed]
    refute Enum.any?(kept, &(&1["id"] == "latissimus-dorsi"))

    # The coach removes one muscle of the thrusters by hand.
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put(
      "/api/org/#{org.slug}/admin/workouts/#{id}/goals",
      Jason.encode!(%{muscles: kept, qualities: suggested["qualities"]})
    )
    |> json_response(200)

    # Then adds pull-ups, written exactly, and publishes without any check answer.
    payload = sectioned([{"", "Thrusters\nPull-ups"}])
    save(conn, org, id, payload, 1)

    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post(
      "/api/org/#{org.slug}/admin/workouts/#{id}/publish",
      Jason.encode!(Map.put(payload, :expected_source_revision, 2))
    )
    |> json_response(200)

    %{"goals" => grown} = goals(conn, org, id)
    assert grown["source"] == "edited"
    assert Enum.any?(grown["muscles"], &(&1["id"] == "latissimus-dorsi"))
    refute Enum.any?(grown["muscles"], &(&1["id"] == removed["id"]))
    # Every muscle the coach kept stays; pull-ups may raise a kept muscle's
    # role (ADR-731: rhomboids are a stabilizer of thrusters, secondary in pull-ups).
    grown_ids = Enum.map(grown["muscles"], & &1["id"])
    assert Enum.all?(kept, &(&1["id"] in grown_ids))

    # ...and no kept muscle loses role (ADR-570: edited goals only grow).
    rank = %{"stabilizer" => 1, "secondary" => 2, "primary" => 3}
    grown_roles = Map.new(grown["muscles"], &{&1["id"], &1["role"]})

    for %{"id" => muscle, "role" => role} <- kept do
      assert rank[grown_roles[muscle]] >= rank[role], muscle
    end
  end
end
