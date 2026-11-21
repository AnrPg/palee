defmodule PaleeWeb.AdminWorkoutKindController do
  @moduledoc """
  ADR-690: the box's own workout types. Whoever writes WODs adds one from
  the picker; owners and admins rename, re-family, hide or merge them in
  Settings › «Τύποι προπόνησης».
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.WorkoutKinds
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias PaleeWeb.Schemas.WorkoutKinds, as: KindSchemas

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:create, :update, :merge]

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:index,
    summary: "The box's view of every workout type: the Palee additions and its own types",
    responses: [ok: {"Catalogue", "application/json", KindSchemas.catalogue()}]
  )

  def index(conn, _params) do
    json(conn, KindSchemas.render_catalogue(WorkoutKinds.catalogue(conn.assigns.tenant_context)))
  end

  operation(:create,
    summary: "Add a workout type to the box (shown again if it was hidden)",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            required: [:label, :family],
            properties: %{
              label: %Schema{type: :string, minLength: 1, maxLength: 80},
              family: KindSchemas.family()
            },
            additionalProperties: false
          }
        }
      }
    },
    responses: [
      created: {"The type", "application/json", KindSchemas.box_kind_envelope()},
      unprocessable_entity: {"Invalid", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, _params) do
    with {:ok, kind} <- WorkoutKinds.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{workout_kind: KindSchemas.render_box_kind(kind)})
    end
  end

  operation(:update,
    summary: "Rename a box type, change its family, or hide/show it",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              label: %Schema{type: :string, minLength: 1, maxLength: 80},
              family: KindSchemas.family(),
              hidden: %Schema{type: :boolean}
            },
            additionalProperties: false
          }
        }
      }
    },
    responses: [
      ok: {"The type", "application/json", KindSchemas.box_kind_envelope()},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, %{id: id}) do
    with {:ok, kind} <-
           WorkoutKinds.update(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{workout_kind: KindSchemas.render_box_kind(kind)})
    end
  end

  operation(:merge,
    summary: "Merge a box type into another type; the box's WODs move to it",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            required: [:into],
            properties: %{into: KindSchemas.ref()},
            additionalProperties: false
          }
        }
      }
    },
    responses: [
      ok:
        {"Merged", "application/json",
         %Schema{
           type: :object,
           required: [:workout_kind, :workouts],
           properties: %{
             workout_kind: KindSchemas.box_kind(),
             workouts: %Schema{type: :integer, description: "WODs moved to the other type"}
           }
         }},
      not_found: {"Not found", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid", "application/json", %Schema{type: :object}}
    ]
  )

  def merge(conn, %{id: id}) do
    with {:ok, %{kind: kind, workouts: workouts}} <-
           WorkoutKinds.merge(conn.assigns.tenant_context, id, conn.body_params.into) do
      json(conn, %{workout_kind: KindSchemas.render_box_kind(kind), workouts: workouts})
    end
  end
end
