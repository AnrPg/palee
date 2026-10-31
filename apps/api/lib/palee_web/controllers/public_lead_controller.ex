defmodule PaleeWeb.PublicLeadController do
  @moduledoc """
  ADR-345: the box's public «Ενδιαφέρομαι» (a form or a join link) for
  people without an account. Rate limited per address; spam gets the same
  answer as a real enquiry; contact consent is required.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Leads.PublicIntake
  alias PaleeWeb.Growth.Params
  alias PaleeWeb.Schemas.Growth, as: G

  action_fallback PaleeWeb.FallbackController

  tags(["Public box page"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:create,
    summary: "Send an enquiry to a box («Ενδιαφέρομαι»)",
    description:
      "Stores a lead for the box, or joins the open one of the same email. Always " <>
        "answers `received`, so the answer says nothing about who is known to the box.",
    parameters: [
      %Parameter{
        name: :slug,
        in: :path,
        required: true,
        schema: %Schema{type: :string, maxLength: 120}
      }
    ],
    request_body: G.body(G.public_lead_body()),
    responses: [
      accepted: {"Received", "application/json", G.public_lead_response()},
      not_found: {"No box with this slug", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, %{slug: slug}) do
    with {:ok, :received} <- PublicIntake.call(slug, Params.stringify(conn.body_params)) do
      conn |> put_status(:accepted) |> json(%{status: "received"})
    end
  end
end
