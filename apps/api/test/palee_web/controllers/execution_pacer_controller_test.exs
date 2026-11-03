defmodule PaleeWeb.ExecutionPacerControllerTest do
  @moduledoc """
  ADR-374 (race your past self) and ADR-375 (the watch) on real executions,
  under the RLS-enforcing runtime role (ConnCase).
  """

  use PaleeWeb.ConnCase, async: false

  alias Palee.Application.MyBody
  alias Palee.Identity.UserContext
  alias Palee.{Identity, Organizations, Workouts}

  setup %{conn: conn} do
    admin = create_user!(:member, "pacer_admin")
    {:ok, admin} = Identity.update_role(admin, :admin)
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
    member = create_user!(:member, "pacer_member")
    other = create_user!(:member, "pacer_other")

    {:ok, context} =
      Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

    {:ok, workout} =
      Workouts.create_workout(context, admin, %{
        title: "Pacer Workout",
        type: "crossfit",
        sections: [
          %{
            name: "Main Set",
            order: 1,
            scoreable: false,
            exercises: [
              %{name: "Thruster", order: 1, prescription_value: 21, prescription_unit: "reps"}
            ]
          }
        ]
      })

    %{conn: conn, member: member, other: other, workout: workout}
  end

  test "the second attempt races the first, split by mark", ctx do
    first = start!(ctx.conn, ctx.member, ctx.workout)

    assert %{"stored" => 2, "total" => 2} =
             ctx.conn
             |> as(ctx.member)
             |> json_post("/api/executions/#{first}/splits", %{
               marks: [
                 %{segment_index: 0, round: 1, elapsed_ms: 60_000},
                 %{segment_index: 0, elapsed_ms: 150_000}
               ]
             })
             |> json_response(200)

    # A resend after being offline is stored once.
    assert %{"stored" => 0, "total" => 2} =
             ctx.conn
             |> as(ctx.member)
             |> json_post("/api/executions/#{first}/splits", %{
               marks: [%{segment_index: 0, round: 1, elapsed_ms: 60_000}]
             })
             |> json_response(200)

    # Nothing to race on a first attempt.
    assert %{"pacer" => %{"previous" => nil, "checkpoints" => []}} =
             ctx.conn
             |> as(ctx.member)
             |> get("/api/executions/#{first}/pacer")
             |> json_response(200)

    complete!(ctx.conn, ctx.member, first)
    second = start!(ctx.conn, ctx.member, ctx.workout)

    ctx.conn
    |> as(ctx.member)
    |> json_post("/api/executions/#{second}/splits", %{
      marks: [%{segment_index: 0, round: 1, elapsed_ms: 55_000}]
    })
    |> json_response(200)

    assert %{"pacer" => pacer} =
             ctx.conn
             |> as(ctx.member)
             |> get("/api/executions/#{second}/pacer")
             |> json_response(200)

    assert pacer["previous"]["execution_id"] == first
    assert pacer["previous"]["same_workout"]
    assert pacer["precision"] == "rounds"

    assert [
             %{"round" => 1, "ghost_at_ms" => 60_000, "at_ms" => 55_000, "delta_ms" => -5_000},
             %{"round" => 0, "ghost_at_ms" => 150_000, "at_ms" => nil, "delta_ms" => nil}
           ] = pacer["checkpoints"]

    # The watch gets the same pace line with its plan.
    assert %{"plan" => plan} =
             ctx.conn
             |> as(ctx.member)
             |> get("/api/executions/#{second}/watch-plan?platform=apple_watch")
             |> json_response(200)

    assert plan["contract_version"] == 1
    assert plan["title"] == "Pacer Workout"
    assert [%{"at_ms" => 60_000}, %{"at_ms" => 150_000}] = plan["pace"]
    assert [%{"movements" => [%{"name" => "Thruster"}]} | _] = plan["segments"]
  end

  test "marks that don't fit, and other people's executions, are refused", ctx do
    execution = start!(ctx.conn, ctx.member, ctx.workout)

    assert %{"code" => "invalid_split_marks"} =
             ctx.conn
             |> as(ctx.member)
             |> json_post("/api/executions/#{execution}/splits", %{
               marks: [%{segment_index: 99, elapsed_ms: 1}]
             })
             |> json_response(422)

    for path <- ["/pacer", "/watch-plan", "/heart-rate"] do
      assert ctx.conn
             |> as(ctx.other)
             |> get("/api/executions/#{execution}#{path}")
             |> json_response(404)
    end

    assert ctx.conn
           |> as(ctx.other)
           |> json_post("/api/executions/#{execution}/splits", %{
             marks: [%{segment_index: 0, elapsed_ms: 1}]
           })
           |> json_response(404)
  end

  test "heart rate needs the health-data consent, is stored once and summarised", ctx do
    execution = start!(ctx.conn, ctx.member, ctx.workout)

    body = %{
      platform: "apple_watch",
      batches: [
        %{sequence: 0, started_offset_ms: 0, interval_ms: 5000, bpm: [120, 130, 140]},
        %{sequence: 1, started_offset_ms: 15_000, interval_ms: 5000, bpm: [150]}
      ]
    }

    assert %{"code" => "health_data_consent_required"} =
             ctx.conn
             |> as(ctx.member)
             |> json_post("/api/executions/#{execution}/heart-rate", body)
             |> json_response(403)

    {:ok, _} = MyBody.grant(UserContext.new(ctx.member), "health_data")

    assert %{"stored" => 2, "total" => 2} =
             ctx.conn
             |> as(ctx.member)
             |> json_post("/api/executions/#{execution}/heart-rate", body)
             |> json_response(200)

    assert %{"stored" => 0, "total" => 2} =
             ctx.conn
             |> as(ctx.member)
             |> json_post("/api/executions/#{execution}/heart-rate", body)
             |> json_response(200)

    assert %{
             "heart_rate" => %{
               "samples" => 4,
               "average_bpm" => 135,
               "max_bpm" => 150,
               "zones" => []
             }
           } =
             ctx.conn
             |> as(ctx.member)
             |> get("/api/executions/#{execution}/heart-rate")
             |> json_response(200)
  end

  test "a progress save leaves split marks: AMRAP round counts become round marks", ctx do
    execution = start!(ctx.conn, ctx.member, ctx.workout)

    version =
      ctx.conn
      |> as(ctx.member)
      |> get("/api/executions/#{execution}")
      |> json_response(200)
      |> get_in(["execution", "lock_version"])

    ctx.conn
    |> as(ctx.member)
    |> patch("/api/executions/#{execution}/progress", %{
      expected_version: version,
      operation_id: Ecto.UUID.generate(),
      checked_exercise_ids: [],
      current_segment_index: 0,
      status: "active",
      paused_elapsed_ms: 0,
      total_elapsed_ms: 90_000,
      section_elapsed_ms: %{},
      segment_cycle_counts: %{"segment:0" => 2}
    })
    |> json_response(200)

    # Rounds 1 and 2 are already there; the timer's own mark is not new.
    assert %{"stored" => 0, "total" => 2} =
             ctx.conn
             |> as(ctx.member)
             |> json_post("/api/executions/#{execution}/splits", %{
               marks: [%{segment_index: 0, round: 1, elapsed_ms: 40_000}]
             })
             |> json_response(200)
  end

  test "the watch offer follows ANR's D8 rules for a box member", ctx do
    offer = fn id, body ->
      ctx.conn
      |> as(ctx.member)
      |> json_post("/api/executions/#{id}/watch-offer", body)
    end

    first = start!(ctx.conn, ctx.member, ctx.workout)

    # Not connected at this moment: nothing, and nothing is counted.
    assert %{"mode" => "none", "reason" => "watch_not_connected", "asked_count" => 0} =
             offer.(first, %{platform: "apple_watch", watch_connected: false})
             |> json_response(200)

    assert %{"mode" => "ask", "reason" => "first_wods", "asked_count" => 1, "ask_limit" => 5} =
             offer.(first, %{platform: "apple_watch", watch_connected: true})
             |> json_response(200)

    # Opening the same WOD again asks again but counts once.
    assert %{"mode" => "ask", "reason" => "not_answered", "asked_count" => 1} =
             offer.(first, %{platform: "apple_watch", watch_connected: true})
             |> json_response(200)

    assert %{"mode" => "start", "answer" => "yes"} =
             ctx.conn
             |> as(ctx.member)
             |> send_json(:put, "/api/executions/#{first}/watch-offer/answer", %{answer: "yes"})
             |> json_response(200)

    assert %{"mode" => "start", "reason" => "answered_yes"} =
             offer.(first, %{platform: "apple_watch", watch_connected: true})
             |> json_response(200)

    complete!(ctx.conn, ctx.member, first)

    assert %{"mode" => "none", "reason" => "execution_closed"} =
             offer.(first, %{platform: "apple_watch", watch_connected: true})
             |> json_response(200)

    # Four more WODs are asked (five in all), then the watch starts on its own.
    for _ <- 1..4 do
      id = start!(ctx.conn, ctx.member, ctx.workout)

      assert %{"mode" => "ask"} =
               offer.(id, %{platform: "wear_os", watch_connected: true}) |> json_response(200)

      complete!(ctx.conn, ctx.member, id)
    end

    sixth = start!(ctx.conn, ctx.member, ctx.workout)

    assert %{"mode" => "start", "reason" => "box_member_after_first_wods", "asked_count" => 5} =
             offer.(sixth, %{platform: "wear_os", watch_connected: true}) |> json_response(200)

    # Nobody asked on this one, so there is nothing to answer.
    assert %{"code" => "watch_offer_not_asked"} =
             ctx.conn
             |> as(ctx.member)
             |> send_json(:put, "/api/executions/#{sixth}/watch-offer/answer", %{answer: "no"})
             |> json_response(409)

    assert ctx.conn
           |> as(ctx.other)
           |> json_post("/api/executions/#{sixth}/watch-offer", %{
             platform: "wear_os",
             watch_connected: true
           })
           |> json_response(404)
  end

  defp start!(conn, user, workout) do
    conn
    |> as(user)
    |> json_post("/api/executions", %{master_workout_id: workout.id, source: "self_selected"})
    |> json_response(201)
    |> get_in(["execution", "id"])
  end

  defp complete!(conn, user, id) do
    conn
    |> as(user)
    |> patch("/api/executions/#{id}/complete", %{section_scores: []})
    |> json_response(200)
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp json_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, :post, path, Jason.encode!(body))
  end

  defp create_user!(role, nickname) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: role,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(user)
    user
  end
end
