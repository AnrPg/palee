defmodule PaleeWeb.PublicStatusController do
  @moduledoc """
  ADR-364 (CP-G4): the public status page data and email subscriptions. No
  sign-in. Reads are cacheable for 30 seconds, so a CDN or a page hosted
  outside the cluster can serve them.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.PublicServiceStatus
  alias PaleeWeb.Schemas.ServiceStatus, as: S
  alias PaleeWeb.ServiceStatusJSON
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Status"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @cache "public, max-age=30"

  operation(:show,
    summary: "The status of Palee now: components, incidents, maintenance",
    security: [],
    responses: [ok: {"Status", "application/json", S.overview()}]
  )

  def show(conn, _params) do
    with {:ok, view} <- PublicServiceStatus.overview() do
      conn |> put_resp_header("cache-control", @cache) |> json(ServiceStatusJSON.overview(view))
    end
  end

  operation(:history,
    summary: "Uptime per component and day (up to 90 days) and past incidents",
    security: [],
    parameters: [
      %Parameter{
        name: :days,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 90}
      }
    ],
    responses: [ok: {"History", "application/json", S.history()}]
  )

  def history(conn, params) do
    with {:ok, view} <- PublicServiceStatus.history(Map.get(params, :days)) do
      conn |> put_resp_header("cache-control", @cache) |> json(ServiceStatusJSON.history(view))
    end
  end

  operation(:subscribe,
    summary: "Ask for status emails (a confirmation email is sent)",
    description:
      "The answer is the same whether the address is new or already subscribed.",
    security: [],
    request_body: S.subscribe_body(),
    responses: [accepted: {"Accepted", "application/json", S.accepted()}]
  )

  def subscribe(conn, _params) do
    with :ok <- PublicServiceStatus.subscribe(conn.body_params) do
      conn |> put_status(:accepted) |> json(%{status: "accepted"})
    end
  end

  operation(:confirm,
    summary: "Confirm status emails with the token from the confirmation email",
    security: [],
    request_body: S.token_body(),
    responses: [ok: {"Confirmed", "application/json", S.accepted()}]
  )

  def confirm(conn, _params) do
    with :ok <- PublicServiceStatus.confirm(conn.body_params) do
      json(conn, %{status: "confirmed"})
    end
  end

  operation(:unsubscribe,
    summary: "Stop status emails with the token from a status email",
    security: [],
    request_body: S.token_body(),
    responses: [ok: {"Removed", "application/json", S.accepted()}]
  )

  def unsubscribe(conn, _params) do
    with :ok <- PublicServiceStatus.unsubscribe(conn.body_params) do
      json(conn, %{status: "removed"})
    end
  end
end
