defmodule PaleeWeb.AdminBoxReviewsController do
  @moduledoc "Staff read the box's reviews and reply; no review can be deleted (ADR-386)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ReviewAsks.{BoxReviews, ReviewReports}
  alias PaleeWeb.Schemas.BoxReviews, as: S
  alias PaleeWeb.Schemas.BoxSite
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Box reviews"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, [json_render_error_v2: true] when action in [:reply, :report]

  operation(:index,
    summary: "The box's reviews (newest first) with the average and the Google listing",
    parameters: [
      %Parameter{name: :limit, in: :query, required: false, schema: %Schema{type: :integer}},
      %Parameter{name: :offset, in: :query, required: false, schema: %Schema{type: :integer}}
    ],
    responses: [ok: {"Reviews", "application/json", S.staff_response()}]
  )

  def index(conn, params) do
    with {:ok, result} <- BoxReviews.for_staff(conn.assigns.tenant_context, params),
         do: json(conn, result)
  end

  operation(:reply,
    summary: "Reply to a review as the box (or edit the reply)",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: BoxSite.body(S.reply_request()),
    responses: [
      ok: {"Review", "application/json", S.review_response()},
      not_found: {"No such review", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid", "application/json", %Schema{type: :object}}
    ]
  )

  def reply(conn, %{id: id}) do
    with {:ok, result} <- BoxReviews.reply(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, result)
  end

  operation(:report,
    summary: "Report a review as the box to the Palee team; the box can never hide a review itself",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: BoxSite.body(S.report_request()),
    responses: [
      ok: {"Reported", "application/json", S.report_response()},
      not_found: {"No such review", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid or my own review", "application/json", %Schema{type: :object}},
      too_many_requests: {"Too many reports today", "application/json", %Schema{type: :object}}
    ]
  )

  def report(conn, %{id: id}) do
    with {:ok, result} <-
           ReviewReports.report_as_box(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, result)
  end
end
