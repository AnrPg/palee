defmodule PaleeWeb.AdminClassWorkoutsController do
  @moduledoc """
  ADR-746: a class's WODs from the staff class page: the whole ordered
  list («+ WOD», order, remove), the coach's «Τώρα», and the WOD a coach
  sets for someone booked (also over their own choice).
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.ClassWorkouts.{
    ChooseClassWorkout,
    SetClassLiveWorkout,
    SetClassWorkouts
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:put_workouts, :put_live, :put_booking_workout]

  @slot_param %Parameter{
    name: :id,
    in: :path,
    description: "Scheduled class ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @booking_param %Parameter{
    name: :booking_id,
    in: :path,
    description: "Booking ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @error_schema %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:code, :error]
  }

  @slot_response %Schema{
    type: :object,
    properties: %{slot: %Schema{type: :object, additionalProperties: true}},
    required: [:slot]
  }

  @booking_response %Schema{
    type: :object,
    properties: %{booking: %Schema{type: :object, additionalProperties: true}},
    required: [:booking]
  }

  operation(:put_workouts,
    summary: "Set every WOD of a class, in order",
    description:
      "ADR-746: the first WOD is the class's WOD; the rest follow it. New WODs are filed in the day's Classes folder. " <>
        "«Τώρα» and the people who chose a removed WOD go back to the first WOD and to «Θα αποφασίσω στο box».",
    parameters: [@slot_param],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{
              workout_ids: %Schema{
                type: :array,
                items: %Schema{type: :string, format: :uuid},
                uniqueItems: true
              }
            },
            required: [:workout_ids]
          }
        }
      }
    },
    responses: [
      ok: {"Slot", "application/json", @slot_response},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Invalid list", "application/json", @error_schema}
    ]
  )

  def put_workouts(conn, %{id: id}) do
    with {:ok, slot} <-
           SetClassWorkouts.call(conn.assigns.tenant_context, id, conn.body_params.workout_ids) do
      json(conn, %{slot: slot})
    end
  end

  operation(:put_live,
    summary: "Point the class's «Τώρα» at one of its WODs",
    description:
      "ADR-746: people who decide at the box, the class timer and box screens follow it. null = the first WOD.",
    parameters: [@slot_param],
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
      ok: {"Slot", "application/json", @slot_response},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Not one of the class's WODs", "application/json", @error_schema}
    ]
  )

  def put_live(conn, %{id: id}) do
    with {:ok, slot} <-
           SetClassLiveWorkout.call(conn.assigns.tenant_context, id, conn.body_params.workout_id) do
      json(conn, %{slot: slot})
    end
  end

  operation(:put_booking_workout,
    summary: "Set the WOD someone booked in the class does",
    description:
      "ADR-746: a coach for anyone booked, also over their own choice. null = «Θα αποφασίσω στο box».",
    parameters: [@slot_param, @booking_param],
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
      ok: {"Booking", "application/json", @booking_response},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Not one of the class's WODs", "application/json", @error_schema}
    ]
  )

  def put_booking_workout(conn, %{id: id, booking_id: booking_id}) do
    actor = Guardian.Plug.current_resource(conn)

    with {:ok, booking} <-
           ChooseClassWorkout.call(
             conn.assigns.tenant_context,
             actor,
             id,
             conn.body_params.workout_id,
             booking_id: booking_id
           ) do
      json(conn, %{booking: present_booking(booking)})
    end
  end

  @doc false
  def present_booking(booking) do
    Map.take(booking, [
      :id,
      :scheduled_class_id,
      :user_id,
      :status,
      :chosen_workout_id,
      :workout_chosen_by_id,
      :workout_chosen_at
    ])
  end
end
