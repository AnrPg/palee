defmodule PaleeWeb.WorkoutKindsTest do
  @moduledoc "ADR-690: box workout types, several types per WOD and the Palee team's queue."

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Palee.TestFixtures

  alias Palee.{Identity, Organizations}
  alias Palee.Application.WorkoutKinds
  alias Palee.Workers.ApplyWorkoutKindDecisionJob

  @locales ~w(en el de es fr it nl pt_PT ru bg ar he)

  describe "box types" do
    test "a coach adds a type; the same name answers the same type", %{conn: conn} do
      {owner, organization} = authenticate(conn, "kinds_owner", :owner)
      coach = join_as(conn, organization, "kinds_coach", :coach)
      base = "/api/org/#{organization.slug}/admin/workout-kinds"

      created =
        coach
        |> jpost(base, %{label: "  Hyrox   Sim ", family: "functional"})
        |> json_response(201)
        |> Map.fetch!("workout_kind")

      assert created["label"] == "Hyrox Sim"
      assert created["family"] == "functional"
      assert created["ref"] == "box:#{created["id"]}"

      again =
        owner
        |> recycle()
        |> jpost(base, %{label: "hyrox sim", family: "strength"})
        |> json_response(201)

      assert again["workout_kind"]["id"] == created["id"]

      assert %{"box" => [listed], "additions" => []} =
               owner |> recycle() |> get(base) |> json_response(200)

      assert listed["id"] == created["id"]

      # The authoring settings carry the same catalogue for the editors.
      assert %{"workout_kinds" => %{"box" => [_]}} =
               owner
               |> recycle()
               |> get("/api/org/#{organization.slug}/admin/workouts/authoring-settings")
               |> json_response(200)
    end

    test "labels are checked and members cannot add types", %{conn: conn} do
      {owner, organization} = authenticate(conn, "kinds_checks", :owner)
      member = join_as(conn, organization, "kinds_member", :member)
      base = "/api/org/#{organization.slug}/admin/workout-kinds"

      assert %{"code" => "workout_kind_label_too_short"} =
               owner |> jpost(base, %{label: "x", family: "functional"}) |> json_response(422)

      assert %{"code" => "workout_kind_label_too_long"} =
               owner
               |> recycle()
               |> jpost(base, %{label: String.duplicate("a", 41), family: "functional"})
               |> json_response(422)

      assert member
             |> recycle()
             |> jpost(base, %{label: "Yoga flow", family: "mind_body"})
             |> json_response(403)
    end

    test "a WOD has several types; a sectioned WOD's types are its sections' union",
         %{conn: conn} do
      {owner, organization} = authenticate(conn, "kinds_multi", :owner)
      kind = create_kind(owner, organization, "Engine Day", "endurance")
      ref = "box:#{kind["id"]}"

      workout =
        publish(owner, organization, %{
          types: ["strength"],
          sections: [
            section(1, types: [ref, "strength"]),
            section(2, types: ["hyrox"])
          ]
        })

      assert Enum.sort(workout["types"]) == Enum.sort(["strength", "hyrox", ref])
      assert workout["families"] == ["functional", "strength", "endurance"]
      # The compatibility `type` is the first built-in kind in catalogue order.
      assert workout["type"] == "hyrox"

      plain = publish(owner, organization, %{types: [ref], sections: [section(1, [])]})
      assert plain["types"] == [ref]
      assert plain["families"] == ["endurance"]
      assert plain["type"] == nil

      assert %{"code" => "unknown_workout_type"} =
               owner
               |> recycle()
               |> publish_conn(organization, %{
                 types: ["box:#{Ecto.UUID.generate()}"],
                 sections: [section(1, [])]
               })
               |> json_response(422)

      # A type is required.
      assert owner
             |> recycle()
             |> publish_conn(organization, %{types: [], sections: [section(1, [])]})
             |> json_response(422)
    end

    test "the library filter matches a WOD with any chosen type or family", %{conn: conn} do
      {owner, organization} = authenticate(conn, "kinds_filter", :owner)
      kind = create_kind(owner, organization, "Mobility Flow", "recovery")
      ref = "box:#{kind["id"]}"

      mixed =
        publish(owner, organization, %{types: ["strength", ref], sections: [section(1, [])]})

      other = publish(owner, organization, %{types: ["yoga"], sections: [section(1, [])]})

      ids = fn type ->
        owner
        |> recycle()
        |> get("/api/org/#{organization.slug}/admin/workouts/choices", %{type: type})
        |> json_response(200)
        |> Map.fetch!("workouts")
        |> Enum.map(& &1["id"])
      end

      assert ids.(ref) == [mixed["id"]]
      assert ids.("strength") == [mixed["id"]]
      assert ids.("recovery") == [mixed["id"]]
      assert ids.("mind_body") == [other["id"]]
      assert ids.("nothing_like_this") == []
      assert mixed["families"] == ["strength", "recovery"]
    end

    test "owners rename, re-family, hide and merge; the box's WODs follow", %{conn: conn} do
      {owner, organization} = authenticate(conn, "kinds_manage", :owner)
      coach = join_as(conn, organization, "kinds_manage_coach", :coach)
      kind = create_kind(owner, organization, "Mettcon", "functional")
      ref = "box:#{kind["id"]}"
      base = "/api/org/#{organization.slug}/admin/workout-kinds/#{kind["id"]}"
      workout = publish(owner, organization, %{types: [ref], sections: [section(1, [])]})

      assert coach |> jpatch(base, %{label: "Metcon"}) |> json_response(403)

      renamed =
        owner
        |> recycle()
        |> jpatch(base, %{label: "Metcon", family: "strength"})
        |> json_response(200)

      assert %{"label" => "Metcon", "family" => "strength"} = renamed["workout_kind"]
      assert fetch_workout(owner, organization, workout["id"])["families"] == ["strength"]

      assert %{"workout_kind" => %{"status" => "hidden"}} =
               owner |> recycle() |> jpatch(base, %{hidden: true}) |> json_response(200)

      assert %{"code" => "invalid_workout_kind"} =
               owner |> recycle() |> jpost("#{base}/merge", %{into: ref}) |> json_response(422)

      assert %{"workout_kind" => %{"status" => "merged"}, "workouts" => 1} =
               owner
               |> recycle()
               |> jpost("#{base}/merge", %{into: "crossfit"})
               |> json_response(200)

      merged = fetch_workout(owner, organization, workout["id"])
      assert merged["types"] == ["crossfit"]
      assert merged["families"] == ["functional"]
      assert merged["type"] == "crossfit"

      assert owner |> recycle() |> jpatch(base, %{label: "Again"}) |> json_response(404)
    end
  end

  describe "the Palee team" do
    setup do
      start_supervised!(
        {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
      )

      vendor = user_fixture(%{nickname: "kinds_vendor"})
      {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
      %{vendor: vendor}
    end

    test "a name is queued from its first box, and a decision moves every box", %{
      conn: conn,
      vendor: vendor
    } do
      {owner_a, box_a} = authenticate(conn, "kinds_box_a", :owner)
      {owner_b, box_b} = authenticate(conn, "kinds_box_b", :owner)
      kind_a = create_kind(owner_a, box_a, "Ζωνη Ταχυτητας", "endurance")
      kind_b = create_kind(owner_b, box_b, "ζώνη ταχύτητας", "functional")

      workout =
        publish(owner_a, box_a, %{types: ["box:#{kind_a["id"]}"], sections: [section(1, [])]})

      platform = put_bearer_token(conn, vendor)

      assert owner_a |> recycle() |> get("/api/platform/workout-kinds") |> json_response(403)

      %{"pending" => pending} =
        platform |> get("/api/platform/workout-kinds") |> json_response(200)

      assert [candidate] = Enum.filter(pending, &(&1["label"] == "Ζωνη Ταχυτητας"))
      assert candidate["boxes"] == 2
      assert candidate["family_votes"] == %{"endurance" => 1, "functional" => 1}

      decision_url = "/api/platform/workout-kinds/#{candidate["id"]}/decision"

      assert %{"code" => "workout_kind_labels_required"} =
               platform
               |> recycle()
               |> jpost(decision_url, %{
                 decision: "adopt",
                 key: "speed_zone",
                 family: "endurance",
                 labels: %{en: "Speed zone"}
               })
               |> json_response(422)

      assert %{"code" => "workout_kind_key_taken"} =
               platform
               |> recycle()
               |> jpost(decision_url, %{
                 decision: "adopt",
                 key: "hyrox",
                 family: "endurance",
                 labels: labels("Speed zone")
               })
               |> json_response(409)

      assert %{"status" => "adopted"} =
               platform
               |> recycle()
               |> jpost(decision_url, %{
                 decision: "adopt",
                 key: "speed_zone",
                 family: "endurance",
                 labels: labels("Speed zone")
               })
               |> json_response(200)

      for organization <- [box_a, box_b] do
        args = %{
          "organization_id" => organization.id,
          "folded" => "ζωνη ταχυτητασ",
          "target" => "speed_zone",
          "decision" => "adopt"
        }

        assert_enqueued(worker: ApplyWorkoutKindDecisionJob, args: args)
        assert :ok = perform_job(ApplyWorkoutKindDecisionJob, args)
      end

      moved = fetch_workout(owner_a, box_a, workout["id"])
      assert moved["types"] == ["speed_zone"]
      assert moved["families"] == ["endurance"]

      assert %{"additions" => [%{"key" => "speed_zone"}], "box" => box_kinds} =
               owner_b
               |> recycle()
               |> get("/api/org/#{box_b.slug}/admin/workout-kinds")
               |> json_response(200)

      assert Enum.all?(box_kinds, &(&1["status"] == "merged"))

      assert Enum.any?(
               Palee.Repo.all(Palee.Notifications.Notification),
               &(&1.type == :workout_kind_adopted or &1.type == "workout_kind_adopted")
             )

      # The new kind is valid everywhere now.
      assert publish(owner_b, box_b, %{types: ["speed_zone"], sections: [section(1, [])]})[
               "families"
             ] == ["endurance"]

      # A decided name is not pending any more.
      assert platform
             |> recycle()
             |> jpost(decision_url, %{decision: "keep"})
             |> json_response(404)

      assert kind_b["family"] == "functional"
    end

    test "one digest a day, none without news", %{conn: conn} do
      {owner, organization} = authenticate(conn, "kinds_digest", :owner)
      _kind = create_kind(owner, organization, "Digest Kind", "dance")
      now = DateTime.utc_now()

      assert {:sent, sent} = WorkoutKinds.send_digest(now)
      assert sent >= 1
      assert :none = WorkoutKinds.send_digest(now)
    end
  end

  test "any signed-in reader names box types by reference", %{conn: conn} do
    {owner, organization} = authenticate(conn, "kinds_lookup", :owner)
    kind = create_kind(owner, organization, "Lookup Kind", "combat")
    reader = user_fixture(%{nickname: "kinds_reader"})

    assert %{"box" => [named]} =
             conn
             |> put_bearer_token(reader)
             |> get("/api/me/workout-kinds", %{refs: "box:#{kind["id"]},strength"})
             |> json_response(200)

    assert named["label"] == "Lookup Kind"
    assert named["family"] == "combat"
  end

  # --- helpers ---

  defp jpost(conn, path, body), do: send_json(conn, :post, path, body)
  defp jpatch(conn, path, body), do: send_json(conn, :patch, path, body)

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp labels(label), do: Map.new(@locales, &{&1, label})

  defp create_kind(conn, organization, label, family) do
    conn
    |> recycle()
    |> jpost("/api/org/#{organization.slug}/admin/workout-kinds", %{label: label, family: family})
    |> json_response(201)
    |> Map.fetch!("workout_kind")
  end

  defp section(order, opts) do
    %{name: "Part #{order}", order: order, exercises: [], free_text_body: "Part #{order}"}
    |> Map.merge(Map.new(List.wrap(opts)))
  end

  defp publish(conn, organization, attrs) do
    conn
    |> recycle()
    |> publish_conn(organization, attrs)
    |> json_response(200)
    |> then(&(&1["workout"] || &1))
  end

  defp publish_conn(conn, organization, attrs) do
    base = "/api/org/#{organization.slug}/admin/workouts"
    draft_id = conn |> post(base) |> json_response(201) |> get_in(["draft", "id"])

    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post(
      "#{base}/#{draft_id}/publish",
      Jason.encode!(
        Map.merge(
          %{
            title: "Kinds #{System.unique_integer([:positive])}",
            authoring_mode: "sectioned_text",
            expected_source_revision: 0
          },
          attrs
        )
      )
    )
  end

  defp fetch_workout(conn, organization, id) do
    conn
    |> recycle()
    |> get("/api/org/#{organization.slug}/admin/workouts/#{id}")
    |> json_response(200)
    |> then(&(&1["workout"] || &1))
  end

  defp join_as(conn, organization, nickname, membership_role) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, user} =
      if membership_role == :member, do: {:ok, user}, else: Identity.update_role(user, :admin)

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: membership_role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    conn |> recycle() |> put_bearer_token(user)
  end

  defp authenticate(conn, nickname, membership_role) do
    {:ok, organization} = Organizations.create_organization(%{name: "#{nickname} Gym"})
    {join_as(conn, organization, nickname, membership_role), organization}
  end
end
