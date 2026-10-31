defmodule PaleeWeb.PlatformStatusController do
  @moduledoc """
  ADR-364 (CP-G4): the status page in the platform console (vendors): live
  probes with their reasons, incidents and maintenance, subscribers.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.PlatformServiceStatus
  alias PaleeWeb.Schemas.ServiceStatus, as: S
  alias PaleeWeb.ServiceStatusJSON
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Platform status"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string, format: :uuid}}

  operation(:show,
    summary: "Probes with reasons, incidents of the last 90 days and subscribers (vendors)",
    responses: [ok: {"Console", "application/json", S.console()}]
  )

  def show(conn, _params) do
    with {:ok, view} <- PlatformServiceStatus.console(conn.assigns.platform_context) do
      json(conn, ServiceStatusJSON.console(view))
    end
  end

  operation(:create,
    summary: "Publish an incident or planned maintenance (vendors)",
    request_body: S.incident_body(),
    responses: [created: {"Incident", "application/json", S.incident()}]
  )

  def create(conn, _params) do
    with {:ok, incident} <-
           PlatformServiceStatus.create_incident(conn.assigns.platform_context, conn.body_params) do
      conn |> put_status(:created) |> json(ServiceStatusJSON.incident(incident))
    end
  end

  operation(:add_update,
    summary: "Add a step to an incident's timeline (vendors)",
    parameters: [@id],
    request_body: S.update_body(),
    responses: [created: {"Incident", "application/json", S.incident()}]
  )

  def add_update(conn, %{id: id}) do
    with {:ok, incident} <-
           PlatformServiceStatus.add_update(conn.assigns.platform_context, id, conn.body_params) do
      conn |> put_status(:created) |> json(ServiceStatusJSON.incident(incident))
    end
  end

  operation(:update,
    summary: "Correct an incident's title, impact or components (vendors)",
    parameters: [@id],
    request_body: S.edit_body(),
    responses: [ok: {"Incident", "application/json", S.incident()}]
  )

  def update(conn, %{id: id}) do
    with {:ok, incident} <-
           PlatformServiceStatus.edit_incident(conn.assigns.platform_context, id, conn.body_params) do
      json(conn, ServiceStatusJSON.incident(incident))
    end
  end
end
