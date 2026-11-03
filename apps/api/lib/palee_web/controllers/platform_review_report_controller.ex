defmodule PaleeWeb.PlatformReviewReportController do
  @moduledoc """
  ADR-397, the platform console's review reports: the Palee team's queue of
  reported box reviews across every box, and its decisions (keep, hide,
  remove) with the statement of reasons the author receives.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.ReviewAsks.ReviewReports
  alias PaleeWeb.Schemas.BoxReviews, as: S
  alias PaleeWeb.Schemas.BoxSite

  action_fallback PaleeWeb.FallbackController

  tags(["Platform review reports"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "Reported reviews (open, oldest first) or the latest decisions (vendors)",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        description: "Default open",
        schema: %Schema{type: :string, enum: ~w(open decided)}
      }
    ],
    responses: [ok: {"Queue", "application/json", S.platform_queue_response()}]
  )

  def index(conn, params) do
    with {:ok, result} <-
           ReviewReports.platform_queue(conn.assigns.platform_context, %{
             "status" => Map.get(params, :status)
           }),
         do: json(conn, result)
  end

  operation(:decide,
    summary: "Keep, hide or remove a reported review, for every open report on it (vendors)",
    parameters: [
      %Parameter{
        name: :review_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: BoxSite.body(S.decision_request()),
    responses: [
      ok: {"Decision", "application/json", S.decision_response()},
      not_found: {"No such review", "application/json", %Schema{type: :object}},
      conflict: {"No open reports", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid", "application/json", %Schema{type: :object}}
    ]
  )

  def decide(conn, %{review_id: review_id}) do
    with {:ok, result} <-
           ReviewReports.platform_decide(
             conn.assigns.platform_context,
             review_id,
             conn.body_params
           ),
         do: json(conn, result)
  end

  operation(:restore,
    summary: "Show a hidden review again, with a statement for its author (vendors)",
    parameters: [
      %Parameter{
        name: :review_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: BoxSite.body(S.restore_request()),
    responses: [
      ok: {"Restored", "application/json", S.decision_response()},
      not_found: {"No such review", "application/json", %Schema{type: :object}},
      conflict: {"Not hidden", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid", "application/json", %Schema{type: :object}}
    ]
  )

  def restore(conn, %{review_id: review_id}) do
    with {:ok, result} <-
           ReviewReports.platform_restore(
             conn.assigns.platform_context,
             review_id,
             conn.body_params
           ),
         do: json(conn, result)
  end
end
