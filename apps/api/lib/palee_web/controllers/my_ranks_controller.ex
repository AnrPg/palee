defmodule PaleeWeb.MyRanksController do
  @moduledoc "The person's own belts and levels at a box, and their diplomas (ADR-377)."

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.MyRanks
  alias PaleeWeb.Schemas.Ranks, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Ranks"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "My rank on each of the box's ladders, progress and history",
    responses: [ok: {"Standing", "application/json", S.standings_response()}]
  )

  def index(conn, _params) do
    with {:ok, result} <- MyRanks.call(conn.assigns.tenant_context), do: json(conn, result)
  end

  operation(:certificate,
    summary: "My diploma for an award, as a PDF",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"PDF", "application/pdf", S.pdf()},
      not_found: {"No such award", "application/json", S.error()}
    ]
  )

  def certificate(conn, %{id: id}) do
    with {:ok, %{filename: filename, data: data}} <-
           MyRanks.certificate(conn.assigns.tenant_context, id) do
      send_download(conn, {:binary, data}, filename: filename, content_type: "application/pdf")
    end
  end
end
