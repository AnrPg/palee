defmodule PaleeWeb.AdminWorkoutGoalsController do
  @moduledoc """
  Staff read and save of a workout's WOD goals, the coach totals of
  «τι ένιωσες» on a workout or a scheduled class (ADR-163), and a class's
  «Φορτίο προγράμματος» (ADR-670).
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.{
    ExerciseMatches,
    GetClassProgrammeLoad,
    GetGoalFeedbackSummary,
    GetWorkoutGoals,
    SaveWorkoutGoals
  }

  alias PaleeWeb.Schemas.WorkoutGoals
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(PaleeWeb.FallbackController)

  tags(["Workouts"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @id %Parameter{
    name: :id,
    in: :path,
    description: "Workout ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @error %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:error]
  }

  operation(:show,
    summary: "A workout's WOD goals and the live suggestion",
    description:
      "Saved goals, or the suggestion from the workout's exercises (saved=false) when none are saved. Drafts included.",
    parameters: [@id],
    responses: [
      ok: {"WOD goals", "application/json", WorkoutGoals.staff_response()},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- GetWorkoutGoals.call(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:update,
    summary: "Save a workout's WOD goals",
    parameters: [@id],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: WorkoutGoals.save_request()}}
    },
    responses: [
      ok: {"WOD goals", "application/json", WorkoutGoals.staff_response()},
      not_found: {"Not found", "application/json", @error},
      unprocessable_entity: {"Invalid goals", "application/json", @error}
    ]
  )

  def update(conn, %{id: id}) do
    with {:ok, result} <-
           SaveWorkoutGoals.call(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:feedback_summary,
    summary: "Coach totals of «τι ένιωσες» on a workout",
    description:
      "Counts only feedback on non-voided entries whose visibility reaches the caller as a coach; shown only from 3 entries.",
    parameters: [@id],
    responses: [
      ok: {"Goal feedback summary", "application/json", WorkoutGoals.feedback_summary()},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def feedback_summary(conn, %{id: id}) do
    with {:ok, result} <- GetGoalFeedbackSummary.for_workout(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:class_feedback_summary,
    summary: "Coach totals of «τι ένιωσες» on a scheduled class",
    description:
      "Entries logged from the class or timed from its bookings, whatever workout version they followed; same rules as the workout summary.",
    parameters: [%{@id | description: "Scheduled class (slot) ID"}],
    responses: [
      ok: {"Goal feedback summary", "application/json", WorkoutGoals.feedback_summary()},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def class_feedback_summary(conn, %{id: id}) do
    with {:ok, result} <-
           GetGoalFeedbackSummary.for_scheduled_class(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:class_programme_load,
    summary: "Muscle groups the same class worked in the previous 7 days (programme load)",
    description:
      "ADR-670: classes of the same class type at the same branch in the 7 gym days before this one; each WOD once per day, with its saved, inherited or suggested goals. Reads the programme only, never members' entries.",
    parameters: [%{@id | description: "Scheduled class (slot) ID"}],
    responses: [
      ok: {"Programme load", "application/json", WorkoutGoals.programme_load()},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def class_programme_load(conn, %{id: id}) do
    with {:ok, result} <- GetClassProgrammeLoad.call(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:exercise_matches,
    summary: "Catalog exercises found in a free-text workout, to confirm before publishing",
    description:
      "ADR-570: reads the saved editor document; an empty list is a normal answer. Links the coach made are skipped, except those whose words no longer name their exercise (kind changed).",
    parameters: [@id],
    responses: [
      ok: {"Exercise matches", "application/json", WorkoutGoals.exercise_matches()},
      not_found: {"Not found", "application/json", @error}
    ]
  )

  def exercise_matches(conn, %{id: id}) do
    with {:ok, result} <- ExerciseMatches.list(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:decide_exercise_matches,
    summary: "Record the coach's answers to the exercise matches",
    description:
      "ADR-570: after the editor saved the answers as links, the box remembers each yes (and forgets a remembered match answered no), and goals the coach edited take the new suggestion only by adding muscles or promoting roles.",
    parameters: [@id],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: WorkoutGoals.exercise_match_decisions()}
      }
    },
    responses: [
      ok: {"Recorded", "application/json", WorkoutGoals.exercise_match_decided()},
      not_found: {"Not found", "application/json", @error},
      unprocessable_entity: {"Invalid decisions", "application/json", @error}
    ]
  )

  def decide_exercise_matches(conn, %{id: id}) do
    with {:ok, result} <-
           ExerciseMatches.decide(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, result)
    end
  end
end
