defmodule PaleeWeb.PlatformSiteDomainsController do
  @moduledoc "Ops: custom domains of box websites by state (ADR-352 §6), for vendors."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.BoxSite.SiteDomainOps
  alias PaleeWeb.Schemas.BoxSite, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Platform"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "Custom domains in a state (default pending_tls: they need an Ingress)",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{
          type: :string,
          enum: ~w(pending_dns pending_tls active broken expired)
        }
      }
    ],
    responses: [
      ok: {"Domains", "application/json", S.ops_domains_response()},
      unprocessable_entity: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def index(conn, params) do
    with {:ok, list} <- SiteDomainOps.list(params["status"]), do: json(conn, list)
  end
end
