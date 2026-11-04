defmodule PaleeWeb.PlatformExerciseCatalogController do
  @moduledoc """
  ADR-461, the vendors' console: typed exercise names that matched nothing,
  approved into the catalog (a new entry or an alias) or rejected, audited.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.ExerciseCatalogReview
  alias PaleeWeb.Schemas.ExerciseCatalogReview, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Platform exercise catalog"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "Exercise names waiting for the catalog (vendors)",
    parameters: S.queue_parameters(),
    responses: [ok: {"Candidates", "application/json", S.queue()}]
  )

  def index(conn, params) do
    with {:ok, result} <- ExerciseCatalogReview.queue(conn.assigns.platform_context, params),
         do: json(conn, result)
  end

  operation(:decide,
    summary: "Approve a name as a new entry or an alias, or reject it (vendors)",
    parameters: [S.id()],
    request_body: S.decision_body(),
    responses: [
      ok: {"Decided", "application/json", S.decided()},
      not_found: {"Error", "application/json", %OpenApiSpex.Schema{type: :object}},
      conflict: {"Error", "application/json", %OpenApiSpex.Schema{type: :object}},
      unprocessable_entity: {"Error", "application/json", %OpenApiSpex.Schema{type: :object}}
    ]
  )

  def decide(conn, %{"id" => id}) do
    with {:ok, result} <-
           ExerciseCatalogReview.decide(conn.assigns.platform_context, id, conn.body_params),
         do: json(conn, result)
  end

  operation(:audit,
    summary: "The latest exercise catalog decisions (vendors)",
    responses: [ok: {"Audit", "application/json", S.audit()}]
  )

  def audit(conn, _params) do
    with {:ok, result} <- ExerciseCatalogReview.audit(conn.assigns.platform_context),
         do: json(conn, result)
  end
end
