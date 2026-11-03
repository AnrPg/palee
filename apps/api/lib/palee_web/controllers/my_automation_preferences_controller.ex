defmodule PaleeWeb.MyAutomationPreferencesController do
  @moduledoc """
  ADR-346: a box member's own choices about the box's automatic messages:
  none at all, not from some recipes, and the birthday (day and month) they
  share for a greeting.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.Automations.MyAutomationPreferences
  alias PaleeWeb.Growth.Params
  alias PaleeWeb.Schemas.Growth, as: G

  action_fallback PaleeWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "My choices about this box's automatic messages",
    responses: [ok: {"Preferences", "application/json", G.my_preferences()}]
  )

  def show(conn, _params),
    do: json(conn, MyAutomationPreferences.show(conn.assigns.tenant_context))

  operation(:update,
    summary: "Change my choices about this box's automatic messages",
    request_body: G.body(G.my_preferences_body()),
    responses: [ok: {"Preferences", "application/json", G.my_preferences()}]
  )

  def update(conn, _params) do
    with {:ok, preferences} <-
           MyAutomationPreferences.update(
             conn.assigns.tenant_context,
             Params.stringify(conn.body_params)
           ) do
      json(conn, preferences)
    end
  end
end
