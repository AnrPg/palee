defmodule PaleeWeb.AdminDoorsController do
  @moduledoc """
  Staff › Settings › branch › «Πόρτες» (ADR-381): each branch's doors, their
  controllers (Shelly, Kisi) and entry rules (`manage_locations`), opening a
  door from the desk (`check_in`) and the access log. Branch-scoped staff
  see and open only their branches' doors.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Access.DoorSettings
  alias PaleeWeb.Schemas.OpenPlatform, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Doors"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:catalog,
    summary: "Door controllers, entry rules' defaults and how long the access log is kept",
    responses: [ok: {"Catalog", "application/json", S.door_catalog()}]
  )

  def catalog(conn, _params), do: json(conn, DoorSettings.catalog())

  operation(:index,
    summary: "The doors, optionally of one branch",
    parameters: [%Parameter{name: :location_id, in: :query, required: false, schema: S.uuid()}],
    responses: [ok: {"Doors", "application/json", S.doors()}]
  )

  def index(conn, params), do: json(conn, DoorSettings.list(ctx(conn), params))

  operation(:create,
    summary: "Add a door with its controller; the controller is checked first",
    description:
      "Answers the door and, once, the event URL for the controller's own notifications.",
    request_body: S.body(S.door_body()),
    responses: [created: {"Door", "application/json", S.door_created()}]
  )

  def create(conn, _params) do
    with {:ok, result} <- DoorSettings.create(ctx(conn), conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:update,
    summary: "Change a door's name, controller settings, key, rules or status",
    parameters: [@id],
    request_body: S.body(S.door_update_body()),
    responses: [ok: {"Door", "application/json", S.one(:door, S.door())}]
  )

  def update(conn, %{id: id}) do
    with {:ok, door} <- DoorSettings.update(ctx(conn), id, conn.body_params),
         do: json(conn, %{door: door})
  end

  operation(:delete,
    summary: "Remove a door (its access log stays until it ages out)",
    parameters: [@id],
    responses: [ok: {"Removed", "application/json", S.ok()}]
  )

  def delete(conn, %{id: id}) do
    with :ok <- DoorSettings.delete(ctx(conn), id), do: json(conn, %{ok: true})
  end

  operation(:rotate_event_token,
    summary: "A new event URL for the controller's notifications (the old one stops)",
    parameters: [@id],
    responses: [ok: {"Event URL", "application/json", S.event_url()}]
  )

  def rotate_event_token(conn, %{id: id}) do
    with {:ok, result} <- DoorSettings.rotate_event_token(ctx(conn), id), do: json(conn, result)
  end

  operation(:unlock,
    summary: "«Άνοιγμα»: open the door from the desk; logged with who opened it",
    parameters: [@id],
    responses: [ok: {"Opened", "application/json", S.unlock_result()}]
  )

  def unlock(conn, %{id: id}) do
    with {:ok, result} <- DoorSettings.unlock(ctx(conn), id), do: json(conn, result)
  end

  operation(:events,
    summary: "The access log, newest first (kept #{Palee.Access.log_days()} days)",
    parameters: [
      %Parameter{name: :door_id, in: :query, required: false, schema: S.uuid()},
      %Parameter{name: :location_id, in: :query, required: false, schema: S.uuid()},
      %Parameter{name: :user_id, in: :query, required: false, schema: S.uuid()},
      %Parameter{
        name: :kind,
        in: :query,
        required: false,
        schema: %Schema{
          type: :string,
          enum: ~w(granted denied unlock_failed staff_unlock door_event)
        }
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 200}
      },
      %Parameter{
        name: :offset,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0}
      }
    ],
    responses: [ok: {"Access log", "application/json", S.access_events()}]
  )

  def events(conn, params), do: json(conn, DoorSettings.events(ctx(conn), params))

  defp ctx(conn), do: conn.assigns.tenant_context
end
