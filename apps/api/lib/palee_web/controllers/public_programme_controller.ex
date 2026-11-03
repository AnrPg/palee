defmodule PaleeWeb.PublicProgrammeController do
  @moduledoc """
  Programmes without an account (ADR-370): the cross-business catalogue,
  a box's programmes and one programme with its preview days and reviews.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Programmes.Storefront
  alias PaleeWeb.Schemas.Programmes, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Public"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @slug %Parameter{name: :slug, in: :path, required: true, schema: %Schema{type: :string}}
  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @not_found [not_found: {"No such box or programme", "application/json", S.error()}]

  operation(:catalogue,
    summary: "Programmes of every business that lists them in the catalogue",
    parameters: [
      %Parameter{
        name: :query,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 60}
      },
      %Parameter{name: :goal, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{name: :level, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 50}
      },
      %Parameter{
        name: :offset,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0}
      }
    ],
    responses: [ok: {"Programmes", "application/json", S.catalogue_response()}]
  )

  def catalogue(conn, params) do
    with {:ok, result} <- Storefront.catalogue(params), do: json(conn, result)
  end

  operation(:index,
    summary: "The programmes a box sells",
    parameters: [@slug],
    responses: [ok: {"Programmes", "application/json", S.box_programmes_response()}] ++ @not_found
  )

  def index(conn, %{slug: slug}) do
    with {:ok, result} <- Storefront.box_programmes(slug), do: json(conn, result)
  end

  operation(:show,
    summary: "One programme: preview days, weeks and published reviews",
    parameters: [@slug, @id],
    responses:
      [ok: {"Programme", "application/json", S.public_programme_response()}] ++ @not_found
  )

  def show(conn, %{slug: slug, id: id}) do
    with {:ok, result} <- Storefront.programme(slug, id), do: json(conn, result)
  end
end
