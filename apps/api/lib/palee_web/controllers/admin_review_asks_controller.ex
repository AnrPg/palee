defmodule PaleeWeb.AdminReviewAsksController do
  @moduledoc "Staff set up Google review asks and see their counts (ADR-355)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ReviewAsks.ReviewAskAdmin
  alias PaleeWeb.Schemas.BoxReviews
  alias PaleeWeb.Schemas.BoxSite, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Google reviews"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, [json_render_error_v2: true] when action in [:update]

  operation(:show,
    summary: "The box's Google Place ID, milestones and whether members are asked",
    responses: [ok: {"Settings", "application/json", S.review_settings_response()}]
  )

  def show(conn, _params) do
    with {:ok, settings} <- ReviewAskAdmin.settings(conn.assigns.tenant_context),
         do: json(conn, settings)
  end

  operation(:update,
    summary: "Set the Google Place ID, milestones and turn asks on or off",
    request_body: S.body(S.review_settings_update()),
    responses: [
      ok: {"Settings", "application/json", S.review_settings_response()},
      conflict: {"Saved meanwhile", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, _params) do
    with {:ok, settings} <- ReviewAskAdmin.update(conn.assigns.tenant_context, conn.body_params),
         do: json(conn, settings)
  end

  operation(:summary,
    summary: "How many members were asked and what they chose (counts only)",
    responses: [ok: {"Summary", "application/json", S.review_summary_response()}]
  )

  def summary(conn, _params) do
    with {:ok, summary} <- ReviewAskAdmin.summary(conn.assigns.tenant_context),
         do: json(conn, summary)
  end

  operation(:places,
    summary: "Find the box's Google listing by name (Places API, ADR-387)",
    parameters: [
      %Parameter{name: :q, in: :query, required: true, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"Matches", "application/json", BoxReviews.places_response()},
      unprocessable_entity: {"Too short", "application/json", %Schema{type: :object}},
      service_unavailable: {"Places unavailable", "application/json", %Schema{type: :object}}
    ]
  )

  def places(conn, params) do
    with {:ok, result} <-
           ReviewAskAdmin.search_places(conn.assigns.tenant_context, Map.get(params, "q")),
         do: json(conn, result)
  end
end
