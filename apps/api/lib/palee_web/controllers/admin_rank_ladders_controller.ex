defmodule PaleeWeb.AdminRankLaddersController do
  @moduledoc "Staff › Ρυθμίσεις › «Βαθμοί»: the box's ladders of belts and levels (ADR-377)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.RankLadders
  alias PaleeWeb.Schemas.Ranks, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Ranks"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string, format: :uuid}}

  operation(:index,
    summary: "The box's ladders, the templates and the belt palette",
    responses: [ok: {"Ladders", "application/json", S.ladders_response()}]
  )

  def index(conn, _params) do
    with {:ok, result} <- RankLadders.list(conn.assigns.tenant_context), do: json(conn, result)
  end

  operation(:create,
    summary: "Create a ladder, from a template or from scratch",
    request_body: S.body(S.ladder_request()),
    responses: [
      created: {"Ladder", "application/json", S.ladder_response()},
      unprocessable_entity: {"Invalid", "application/json", S.error()}
    ]
  )

  def create(conn, _params) do
    with {:ok, ladder} <- RankLadders.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{ladder: ladder})
    end
  end

  operation(:update,
    summary: "Change a ladder and its ranks (a rank someone holds cannot be removed)",
    parameters: [@id],
    request_body: S.body(S.ladder_request()),
    responses: [
      ok: {"Ladder", "application/json", S.ladder_response()},
      not_found: {"No such ladder", "application/json", S.error()},
      conflict: {"A removed rank is held", "application/json", S.error()},
      unprocessable_entity: {"Invalid", "application/json", S.error()}
    ]
  )

  def update(conn, %{id: id}) do
    with {:ok, ladder} <- RankLadders.update(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, %{ladder: ladder})
  end

  operation(:delete,
    summary: "Archive a ladder; its promotions stay in people's history",
    parameters: [@id],
    responses: [
      no_content: "Archived",
      not_found: {"No such ladder", "application/json", S.error()}
    ]
  )

  def delete(conn, %{id: id}) do
    with :ok <- RankLadders.archive(conn.assigns.tenant_context, id),
         do: send_resp(conn, :no_content, "")
  end
end
