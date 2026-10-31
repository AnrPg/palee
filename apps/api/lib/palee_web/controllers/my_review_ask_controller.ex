defmodule PaleeWeb.MyReviewAskController do
  @moduledoc "A member's Google review ask (ADR-355): shown at a good moment, never gated or rewarded."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ReviewAsks.MemberReviewAsk
  alias PaleeWeb.Schemas.BoxSite, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Google reviews"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, [json_render_error_v2: true] when action in [:respond]

  operation(:show,
    summary: "The review ask to show now, or null",
    responses: [ok: {"Ask", "application/json", S.review_ask_response()}]
  )

  def show(conn, _params) do
    with {:ok, ask} <- MemberReviewAsk.current(conn.assigns.tenant_context), do: json(conn, ask)
  end

  operation(:respond,
    summary: "Record what the member chose: opened Google, later or dismissed",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: S.body(S.review_respond_request()),
    responses: [
      ok: {"Ask", "application/json", S.review_ask_response()},
      not_found: {"No such ask", "application/json", %Schema{type: :object}},
      conflict: {"Already answered", "application/json", %Schema{type: :object}}
    ]
  )

  def respond(conn, %{id: id}) do
    with {:ok, ask} <-
           MemberReviewAsk.respond(conn.assigns.tenant_context, id, conn.body_params.action),
         do: json(conn, ask)
  end

  operation(:opt_out,
    summary: "Never ask me for a review at this box again",
    responses: [ok: {"Opted out", "application/json", S.review_opt_out_response()}]
  )

  def opt_out(conn, _params) do
    with {:ok, result} <- MemberReviewAsk.set_opt_out(conn.assigns.tenant_context, true),
         do: json(conn, result)
  end

  operation(:opt_in,
    summary: "Allow review asks at this box again",
    responses: [ok: {"Opted in", "application/json", S.review_opt_out_response()}]
  )

  def opt_in(conn, _params) do
    with {:ok, result} <- MemberReviewAsk.set_opt_out(conn.assigns.tenant_context, false),
         do: json(conn, result)
  end
end
