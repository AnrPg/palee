defmodule PaleeWeb.ClassVariantController do
  @moduledoc """
  ADR-785: a member's «Παραλλαγή» of one class after it is made.

    * `update_mine` – the member does their variant (`active: true`) or a
      WOD of the class (`false`); the variant stays either way.
    * `keep` – staff, «Κράτησέ τη» on the roster's «Το WOD άλλαξε μετά την
      παραλλαγή».
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.ClassVariants
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:update_mine, :keep]

  @error_schema %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:code, :error]
  }

  @slot_id %Parameter{
    name: :id,
    in: :path,
    description: "Scheduled class ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @ok_schema %Schema{
    type: :object,
    properties: %{ok: %Schema{type: :boolean}},
    required: [:ok]
  }

  operation(:update_mine,
    summary: "Do my variant of the class, or a WOD of the class",
    description:
      "ADR-785: active=false goes back to the class's WODs (the variant stays); active=true does the variant again.",
    parameters: [@slot_id],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{active: %Schema{type: :boolean}},
            required: [:active]
          }
        }
      }
    },
    responses: [
      ok: {"Saved", "application/json", @ok_schema},
      not_found: {"No variant of mine in this class", "application/json", @error_schema}
    ]
  )

  def update_mine(conn, %{id: id}) do
    actor = Guardian.Plug.current_resource(conn)

    with :ok <-
           ClassVariants.set_active(
             conn.assigns.tenant_context,
             actor,
             id,
             conn.body_params.active
           ) do
      json(conn, %{ok: true})
    end
  end

  operation(:keep,
    summary: "Keep a member's variant after the class WOD changed",
    description:
      "ADR-785: «Κράτησέ τη». The class WOD as it reads now becomes the variant's starting point, so the roster stops saying it changed.",
    parameters: [
      @slot_id,
      %Parameter{
        name: :assignment_id,
        in: :path,
        description: "The variant (assigned workout) ID",
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"Kept", "application/json", @ok_schema},
      not_found: {"No such variant of this class", "application/json", @error_schema}
    ]
  )

  def keep(conn, %{id: id, assignment_id: assignment_id}) do
    with :ok <- ClassVariants.keep(conn.assigns.tenant_context, id, assignment_id) do
      json(conn, %{ok: true})
    end
  end
end
