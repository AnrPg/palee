defmodule PaleeWeb.MyCoachPayController do
  @moduledoc "A staff member's own approved pay statements and their PDF (ADR-341, ADR-382)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.CoachPay.CoachPayService
  alias PaleeWeb.Schemas.CoachPay, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Coach pay"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "My pay statements (approved periods only), newest first, with totals",
    responses: [ok: {"Statements", "application/json", S.my_statements()}]
  )

  def index(conn, _params),
    do: json(conn, CoachPayService.my_statements(conn.assigns.tenant_context))

  operation(:payslip,
    summary: "My pay statement of an approved period as PDF («Εκκαθαριστικό»)",
    parameters: [
      %Parameter{
        name: :period_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :language,
        in: :query,
        required: false,
        description: "el en de fr it nl es pt-PT ru bg",
        schema: %Schema{type: :string}
      }
    ],
    responses: [ok: {"PDF", "application/pdf", %Schema{type: :string, format: :binary}}]
  )

  def payslip(conn, %{period_id: period_id} = params) do
    with {:ok, file} <-
           CoachPayService.my_payslip(
             conn.assigns.tenant_context,
             period_id,
             Map.get(params, :language)
           ) do
      PaleeWeb.CoachPayFiles.send_pdf(conn, file)
    end
  end
end
