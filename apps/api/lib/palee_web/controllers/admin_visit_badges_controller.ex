defmodule PaleeWeb.AdminVisitBadgesController do
  @moduledoc "ADR-359 (CP-E1): visit badges («Πρώτη επίσκεψη», «Επισκέπτης») of a class's seats."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.VisitBadges
  alias PaleeWeb.Schemas.TrainingFloor, as: S
  alias OpenApiSpex.Schema

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "Visit badges of every seat of a class (first visit, guest, trial, how they came)",
    parameters: [
      id: [in: :path, required: true, schema: %Schema{type: :string, format: :uuid}]
    ],
    responses: [
      ok: {"Badges", "application/json", S.class_visit_badges()},
      not_found: {"No such class", "application/json", S.error()},
      forbidden: {"Not one of your branches", "application/json", S.error()}
    ]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- VisitBadges.for_class(conn.assigns.tenant_context, id),
         do: json(conn, result)
  end
end
