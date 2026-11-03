defmodule PaleeWeb.MyBoxReviewsController do
  @moduledoc "A member reads the box's reviews and writes their own (ADR-386)."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.ReviewAsks.{BoxReviews, ReviewReports}
  alias PaleeWeb.Schemas.BoxReviews, as: S
  alias PaleeWeb.Schemas.BoxSite
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Box reviews"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:save, :report]

  operation(:index,
    summary: "The box's reviews (newest first), the average, mine and whether I may write one",
    parameters: [
      %Parameter{name: :limit, in: :query, required: false, schema: %Schema{type: :integer}},
      %Parameter{name: :offset, in: :query, required: false, schema: %Schema{type: :integer}}
    ],
    responses: [ok: {"Reviews", "application/json", S.member_response()}]
  )

  def index(conn, params) do
    with {:ok, result} <- BoxReviews.for_member(conn.assigns.tenant_context, params),
         do: json(conn, result)
  end

  operation(:save,
    summary: "Write or edit my review of the box (only after checking in there)",
    request_body: BoxSite.body(S.review_request()),
    responses: [
      ok: {"Review", "application/json", S.review_response()},
      forbidden: {"Never checked in here", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Invalid", "application/json", %Schema{type: :object}}
    ]
  )

  def save(conn, _params) do
    with {:ok, result} <- BoxReviews.save_mine(conn.assigns.tenant_context, conn.body_params),
         do: json(conn, result)
  end

  operation(:delete,
    summary: "Delete my review of the box",
    responses: [no_content: "Deleted"]
  )

  def delete(conn, _params) do
    with :ok <- BoxReviews.delete_mine(conn.assigns.tenant_context),
         do: send_resp(conn, :no_content, "")
  end

  operation(:report,
    summary: "Report a review of my box to the Palee team (it stays up until they decide)",
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
      unprocessable_entity:
        {"Invalid or my own review", "application/json", %Schema{type: :object}},
      too_many_requests: {"Too many reports today", "application/json", %Schema{type: :object}}
    ]
  )

  def report(conn, %{id: id}) do
    with {:ok, result} <-
           ReviewReports.report_as_member(conn.assigns.tenant_context, id, conn.body_params),
         do: json(conn, result)
  end
end
