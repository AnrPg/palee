defmodule PaleeWeb.AnatomyAtlasController do
  @moduledoc """
  The anatomy atlas (ADR-164): the member's own muscle coverage across every
  provider, a client's coverage for their coach (ADR-670), and the exercises
  of the current gym that train one node.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Application.{GetClientAtlas, GetMyAtlas, ListAtlasNodeExercises}
  alias PaleeWeb.Schemas.AnatomyAtlas
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(PaleeWeb.FallbackController)

  tags(["Anatomy"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @not_found {"Not found", "application/json",
              %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}

  operation(:show,
    summary: "Your muscle coverage across every provider, for the anatomy atlas",
    parameters: [
      %Parameter{
        name: :range,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["1w", "4w", "12w"], default: "4w"}
      }
    ],
    responses: [ok: {"Atlas coverage", "application/json", AnatomyAtlas.atlas_response()}]
  )

  def show(conn, params) do
    query = %{"range" => Map.get(params, :range)}

    with {:ok, atlas} <- GetMyAtlas.call(conn.assigns.user_context, query) do
      json(conn, atlas)
    end
  end

  operation(:client,
    summary:
      "A client's muscle coverage for the atlas, from what they share with this gym's coaches",
    description:
      "ADR-670: same rules as the client's progress depth (ADR-165); same shape as the member's own atlas.",
    parameters: [
      %Parameter{
        name: :user_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :range,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["1w", "4w", "12w"], default: "4w"}
      }
    ],
    responses: [
      ok: {"Atlas coverage", "application/json", AnatomyAtlas.atlas_response()},
      forbidden: @not_found,
      not_found: @not_found
    ]
  )

  def client(conn, %{user_id: user_id} = params) do
    query = %{"range" => Map.get(params, :range)}

    with {:ok, atlas} <- GetClientAtlas.call(conn.assigns.tenant_context, user_id, query) do
      json(conn, atlas)
    end
  end

  operation(:exercises,
    summary: "Exercises that train an atlas node, with the gym's videos",
    parameters: [
      %Parameter{
        name: :node_id,
        in: :path,
        required: true,
        description: "Taxonomy node id (region, group or head)",
        schema: %Schema{type: :string}
      }
    ],
    responses: [
      ok: {"Node exercises", "application/json", AnatomyAtlas.node_exercises_response()},
      not_found: @not_found
    ]
  )

  def exercises(conn, %{node_id: node_id}) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, result} <- ListAtlasNodeExercises.call(conn.assigns.tenant_context, actor, node_id) do
      json(conn, result)
    end
  end
end
