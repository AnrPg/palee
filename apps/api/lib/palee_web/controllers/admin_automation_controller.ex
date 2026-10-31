defmodule PaleeWeb.AdminAutomationController do
  @moduledoc """
  ADR-346: the box's «Αυτοματισμοί»: the ready recipes with their switch,
  text, channels and delay, a preview, and the recent messages.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Automations.StaffAutomations
  alias PaleeWeb.Growth.Params
  alias PaleeWeb.Schemas.Growth, as: G

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Automations"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @recipe %Parameter{
    name: :recipe,
    in: :path,
    required: true,
    schema: %Schema{type: :string, enum: Palee.Automations.recipe_keys()}
  }

  @locale %Parameter{
    name: :locale,
    in: :query,
    description: "Language of the default texts (default `el`)",
    schema: %Schema{type: :string, maxLength: 8}
  }

  operation(:index,
    summary: "The ready recipes as the box has them",
    parameters: [@locale],
    responses: [ok: {"Recipes", "application/json", G.recipe_list()}]
  )

  def index(conn, params),
    do: json(conn, StaffAutomations.index(context(conn), Map.get(params, :locale, "el")))

  operation(:update,
    summary: "Switch a recipe on or off, or change its text, channels, delay or settings",
    description: "Switching a recipe off cancels the messages it had queued.",
    parameters: [@recipe, @locale],
    request_body: G.body(G.recipe_update_body()),
    responses: [ok: {"Recipe", "application/json", G.one(:recipe, G.recipe())}]
  )

  def update(conn, %{recipe: recipe} = params) do
    with {:ok, view} <-
           StaffAutomations.update(
             context(conn),
             recipe,
             Params.stringify(conn.body_params),
             Map.get(params, :locale, "el")
           ) do
      json(conn, %{recipe: view})
    end
  end

  operation(:preview,
    summary: "The message as a person would get it (sample name)",
    parameters: [@recipe],
    request_body: G.body(G.recipe_preview_body()),
    responses: [ok: {"Preview", "application/json", G.recipe_preview()}]
  )

  def preview(conn, %{recipe: recipe}) do
    with {:ok, preview} <-
           StaffAutomations.preview(context(conn), recipe, Params.stringify(conn.body_params)) do
      json(conn, preview)
    end
  end

  operation(:deliveries,
    summary: "Recent automatic messages, newest first",
    parameters: [
      %Parameter{name: :recipe, in: :query, schema: %Schema{type: :string}},
      %Parameter{name: :status, in: :query, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 200}
      }
    ],
    responses: [
      ok:
        {"Messages", "application/json",
         G.one(:deliveries, %Schema{type: :array, items: G.delivery()})}
    ]
  )

  def deliveries(conn, params) do
    params =
      params
      |> Params.stringify()
      |> Map.new(fn {k, v} -> {k, if(is_integer(v), do: to_string(v), else: v)} end)

    json(conn, %{deliveries: StaffAutomations.deliveries(context(conn), params)})
  end

  defp context(conn), do: conn.assigns.tenant_context
end
