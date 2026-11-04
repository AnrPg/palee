defmodule PaleeWeb.PlatformFoodMissesController do
  @moduledoc """
  ADR-421, the platform console's «Barcode χωρίς προϊόν»: barcodes members
  scanned that no source had, per country, most scanned first. No person.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Foods
  alias PaleeWeb.Schemas.Foods, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Platform food misses"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "Barcodes no source had, most scanned first (vendors)",
    parameters: [
      %Parameter{
        name: :country,
        in: :query,
        required: false,
        description: "ISO 3166 alpha-2",
        schema: %Schema{type: :string, pattern: "^[A-Za-z]{2}$"}
      }
    ],
    responses: [ok: {"Misses", "application/json", S.barcode_misses_response()}]
  )

  def index(conn, params) do
    with {:ok, result} <-
           Foods.barcode_misses(conn.assigns.platform_context, %{
             "country" => Map.get(params, :country)
           }),
         do: json(conn, result)
  end
end
