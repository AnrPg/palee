defmodule PaleeWeb.MyCoachPayController do
  @moduledoc "A coach's own approved pay statements (ADR-341)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.CoachPay.CoachPayService
  alias PaleeWeb.Schemas.CoachPay, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Coach pay"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "My pay statements (approved periods only), newest first",
    responses: [ok: {"Statements", "application/json", S.my_statements()}]
  )

  def index(conn, _params),
    do: json(conn, CoachPayService.my_statements(conn.assigns.tenant_context))
end
