defmodule PaleeWeb.PlatformWorkoutKindController do
  @moduledoc """
  ADR-690: the Palee team's queue of workout type names (box types and the
  public page's discipline suggestions in one list) and its decisions.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.WorkoutKinds
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias PaleeWeb.Schemas.WorkoutKinds, as: KindSchemas

  action_fallback PaleeWeb.FallbackController

  tags(["Platform"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "Workout type names waiting for the Palee team, and the latest decisions",
    responses: [
      ok:
        {"Queue", "application/json",
         %Schema{
           type: :object,
           required: [:pending, :decided, :additions],
           properties: %{
             pending: %Schema{type: :array, items: KindSchemas.candidate()},
             decided: %Schema{type: :array, items: KindSchemas.candidate()},
             additions: %Schema{type: :array, items: KindSchemas.addition()}
           }
         }}
    ]
  )

  def index(conn, _params) do
    %{pending: pending, decided: decided} = WorkoutKinds.queue()

    json(conn, %{
      pending: Enum.map(pending, &KindSchemas.render_candidate/1),
      decided: Enum.map(decided, &KindSchemas.render_candidate/1),
      additions: Enum.map(WorkoutKinds.additions(), &KindSchemas.render_addition/1)
    })
  end

  operation(:decide,
    summary: "Decide a name: a new kind for everyone, the same as a kind, or kept for the boxes",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
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
            required: [:decision],
            properties: %{
              decision: %Schema{type: :string, enum: ["adopt", "alias", "keep"]},
              key: %Schema{type: :string, pattern: "^[a-z][a-z0-9_]{1,47}$"},
              family: KindSchemas.family(),
              labels: KindSchemas.labels_request(),
              target: %Schema{type: :string, pattern: "^[a-z][a-z0-9_]{1,47}$"}
            },
            additionalProperties: false
          }
        }
      }
    },
    responses: [
      ok: {"Decided", "application/json", KindSchemas.candidate()},
      not_found: {"Not pending", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid", "application/json", %Schema{type: :object}}
    ]
  )

  def decide(conn, %{id: id}) do
    %Palee.Organizations.PlatformContext{user_id: actor_id} = conn.assigns.platform_context

    with {:ok, candidate} <- WorkoutKinds.decide(id, conn.body_params, actor_id) do
      json(conn, KindSchemas.render_candidate(candidate))
    end
  end
end
