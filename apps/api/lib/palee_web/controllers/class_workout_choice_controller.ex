defmodule PaleeWeb.ClassWorkoutChoiceController do
  @moduledoc """
  ADR-746: the WOD a member does in a class with several («Ποιο WOD;»,
  the live switch, «Ακολούθησε» = null). Their booking keeps its seat.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.ClassWorkouts.ChooseClassWorkout
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, [json_render_error_v2: true] when action in [:update]

  @error_schema %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:code, :error]
  }

  operation(:update,
    summary: "Choose which of the class's WODs I do",
    description:
      "ADR-746: on the caller's own booking of the class. null = «Θα αποφασίσω στο box»: follow the coach's «Τώρα».",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        description: "Scheduled class ID",
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{workout_id: %Schema{type: :string, format: :uuid, nullable: true}},
            required: [:workout_id]
          }
        }
      }
    },
    responses: [
      ok:
        {"Booking", "application/json",
         %Schema{
           type: :object,
           properties: %{booking: %Schema{type: :object, additionalProperties: true}},
           required: [:booking]
         }},
      not_found: {"No booking of mine in this class", "application/json", @error_schema},
      unprocessable_entity: {"Not one of the class's WODs", "application/json", @error_schema}
    ]
  )

  def update(conn, %{id: id}) do
    actor = Guardian.Plug.current_resource(conn)

    with {:ok, booking} <-
           ChooseClassWorkout.call(
             conn.assigns.tenant_context,
             actor,
             id,
             conn.body_params.workout_id
           ) do
      json(conn, %{booking: PaleeWeb.AdminClassWorkoutsController.present_booking(booking)})
    end
  end
end
