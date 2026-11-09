defmodule PaleeWeb.AdminWorkoutFreeTextControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Identity, Organizations}

  test "admin receives canonical fields, actionable issues and suggestions", %{conn: conn} do
    {conn, organization} = authenticate(conn, "free_text_ai_admin", :owner)

    response =
      conn
      |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{
        text: "Back sqaut 5x5 @ 100kg",
        locale: "el"
      })
      |> json_response(200)

    assert response["workout"]["title"] == "Back squat day"
    assert [%{"exercises" => [exercise]}] = response["workout"]["sections"]
    assert exercise["load_value"] == 100

    assert [issue] = response["issues"]
    assert issue["message"] == "locale=el"
    assert issue["required"] == true

    assert issue["suggestion"]["text_edit"] == %{
             "find" => "Back sqaut",
             "replace" => "Back squat"
           }

    assert Enum.any?(
             response["suggestions"],
             &(&1["path"] == "sections.0.exercises.0.rest_seconds" and &1["value"] == 120)
           )

    assert response["summary"]["blocking"] == 0
  end

  test "blank text is rejected with an actionable code", %{conn: conn} do
    {conn, organization} = authenticate(conn, "free_text_ai_blank", :owner)

    response =
      conn
      |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{text: "   "})
      |> json_response(422)

    assert response["code"] == "text_required"
  end

  test "assistant outages map to explicit status codes", %{conn: conn} do
    {conn, organization} = authenticate(conn, "free_text_ai_outage", :owner)

    Process.put(:fake_workout_text_analyzer, fn _text, _options ->
      {:error, :analyzer_not_configured}
    end)

    response =
      conn
      |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{text: "Run 5k"})
      |> json_response(503)

    assert response["code"] == "analyzer_not_configured"
  end

  # The edge gateway replaces upstream 502s with its own HTML page, which hides
  # the JSON code from the browser. Provider failures answer 424 instead.
  for reason <- [:analyzer_quota_exhausted, :analyzer_unavailable, :analyzer_invalid_response] do
    test "#{reason} answers 424 with an explicit code", %{conn: conn} do
      {conn, organization} =
        authenticate(conn, "ft_ai_#{System.unique_integer([:positive])}", :owner)

      Process.put(:fake_workout_text_analyzer, fn _text, _options ->
        {:error, unquote(reason)}
      end)

      response =
        conn
        |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{
          text: "Run 5k"
        })
        |> json_response(424)

      assert response["code"] == Atom.to_string(unquote(reason))
    end
  end

  test "members cannot use the workout assistant", %{conn: conn} do
    {conn, organization} = authenticate(conn, "free_text_ai_member", :member)

    conn
    |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{text: "Run 5k"})
    |> json_response(403)
  end

  describe "ADR-180: the gym's WOD assistant switch" do
    test "is on by default, and off it stops the assistant before any call", %{conn: conn} do
      {conn, organization} = authenticate(conn, "free_text_ai_switch", :owner)
      base = "/api/org/#{organization.slug}/admin"

      assert %{"wod_assistant_enabled" => true} =
               conn |> get("#{base}/workouts/authoring-settings") |> json_response(200)

      assert %{"workouts" => %{"wod_assistant_enabled" => false}} =
               conn
               |> recycle()
               |> put_req_header("content-type", "application/json")
               |> patch(
                 "#{base}/settings",
                 Jason.encode!(%{workouts: %{wod_assistant_enabled: false}})
               )
               |> json_response(200)

      assert %{"wod_assistant_enabled" => false} =
               conn
               |> recycle()
               |> get("#{base}/workouts/authoring-settings")
               |> json_response(200)

      Process.put(:fake_workout_text_analyzer, fn _text, _options ->
        flunk("the assistant must not be called when the gym switched it off")
      end)

      assert %{"code" => "assistant_disabled"} =
               conn
               |> recycle()
               |> put_req_header("content-type", "application/json")
               |> post("#{base}/workouts/free-text/analyze", Jason.encode!(%{text: "Run 5k"}))
               |> json_response(403)
    end

    test "ADR-275: the gym picks the workout kinds its editors offer", %{conn: conn} do
      {conn, organization} = authenticate(conn, "free_text_workout_types", :owner)
      base = "/api/org/#{organization.slug}/admin"
      all = Enum.map(Palee.Workouts.supported_workout_types(), &to_string/1)

      assert %{"workout_types" => ^all} =
               conn |> get("#{base}/workouts/authoring-settings") |> json_response(200)

      assert "muay_thai" in all and "dance" in all and "aerobics" in all

      patch_types = fn types ->
        conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> patch("#{base}/settings", Jason.encode!(%{workouts: %{workout_types: types}}))
      end

      # Stored in catalogue order, whatever order the request used.
      assert %{"workouts" => %{"workout_types" => ["crossfit", "boxing"]}} =
               patch_types.(["boxing", "crossfit"]) |> json_response(200)

      assert %{"workout_types" => ["crossfit", "boxing"], "wod_assistant_enabled" => true} =
               conn
               |> recycle()
               |> get("#{base}/workouts/authoring-settings")
               |> json_response(200)

      assert patch_types.([]) |> json_response(422)
      assert patch_types.(["karaoke"]) |> json_response(422)

      assert %{"workouts" => %{"workout_types" => nil}} =
               patch_types.(nil) |> json_response(200)

      assert %{"workout_types" => ^all} =
               conn
               |> recycle()
               |> get("#{base}/workouts/authoring-settings")
               |> json_response(200)
    end

    test "a member cannot read the authoring settings", %{conn: conn} do
      {conn, organization} = authenticate(conn, "free_text_ai_switch_member", :member)

      conn
      |> get("/api/org/#{organization.slug}/admin/workouts/authoring-settings")
      |> json_response(403)
    end
  end

  describe "ADR-571: frequent timers" do
    test "a coach with no history gets the stock chips", %{conn: conn} do
      {conn, organization} = authenticate(conn, "frequent_timers_new", :owner)

      assert %{"presets" => presets} =
               conn
               |> get("/api/org/#{organization.slug}/admin/workouts/frequent-timers")
               |> json_response(200)

      assert Enum.map(presets, & &1["source"]) == ["stock", "stock", "stock"]
      assert Enum.map(presets, & &1["preset"]["format"]) == ["amrap", "emom", "for_time"]
    end

    test "the coach's own most used timers come first, then the gym's", %{conn: conn} do
      {owner_conn, organization} = authenticate(conn, "frequent_timers_owner", :owner)
      coach_conn = join_as(build_conn(), organization, "frequent_timers_coach", :owner)

      emom4 = %{format: "emom", interval_seconds: 60, rounds: 4}
      amrap10 = %{format: "amrap", duration_seconds: 600}
      amrap20 = %{format: "amrap", duration_seconds: 1200}

      # The coach: EMOM 4 three times, AMRAP 10 once, «No time» (never a chip).
      publish_sectioned(coach_conn, organization, [emom4, emom4, nil])
      publish_sectioned(coach_conn, organization, [Map.put(emom4, :rest_seconds, 30), amrap10])
      # Another coach of the gym: AMRAP 20 twice; it tops up the third chip.
      publish_sectioned(owner_conn, organization, [amrap20, amrap20])

      assert %{"presets" => presets} =
               coach_conn
               |> get("/api/org/#{organization.slug}/admin/workouts/frequent-timers")
               |> json_response(200)

      assert [
               %{
                 "source" => "author",
                 "uses" => 3,
                 "preset" => %{"format" => "emom", "rounds" => 4, "interval_seconds" => 60}
               },
               %{
                 "source" => "author",
                 "uses" => 1,
                 "preset" => %{"format" => "amrap", "duration_seconds" => 600}
               },
               %{
                 "source" => "gym",
                 "uses" => 2,
                 "preset" => %{"format" => "amrap", "duration_seconds" => 1200}
               }
             ] = presets

      # The EMOM's stray rest is not part of an EMOM: one chip, not two.
      refute Map.has_key?(hd(presets)["preset"], "rest_seconds")
    end
  end

  defp publish_sectioned(conn, organization, timers) do
    base = "/api/org/#{organization.slug}/admin/workouts"
    draft_id = conn |> recycle() |> post(base) |> json_response(201) |> get_in(["draft", "id"])

    sections =
      timers
      |> Enum.with_index(1)
      |> Enum.map(fn {timer, order} ->
        %{
          name: "",
          order: order,
          exercises: [],
          free_text_body: "Part #{order}",
          timer_preset: timer
        }
      end)

    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post(
      "#{base}/#{draft_id}/publish",
      Jason.encode!(%{
        title: "Timers #{System.unique_integer([:positive])}",
        type: "crossfit",
        authoring_mode: "sectioned_text",
        expected_source_revision: 0,
        sections: sections
      })
    )
    |> json_response(200)
  end

  defp join_as(conn, organization, nickname, membership_role) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, user} = Identity.update_role(user, :admin)

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: membership_role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    put_bearer_token(conn, user)
  end

  defp authenticate(conn, nickname, membership_role) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, user} =
      if membership_role == :member, do: {:ok, user}, else: Identity.update_role(user, :admin)

    {:ok, organization} = Organizations.create_organization(%{name: "#{nickname} Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: membership_role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {put_bearer_token(conn, user), organization}
  end
end
