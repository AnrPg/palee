defmodule PaleeWeb.DoorAccessController do
  @moduledoc """
  Doors (ADR-381): a member opens the door from the app with the same proof
  of presence as the check-in scan, and a door controller posts its own
  events (no session: the door's secret event token).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias Palee.Application.Access.DoorAccess
  alias PaleeWeb.Schemas.OpenPlatform, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Doors"])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:open,
    summary: "Open the door: proof of presence, then the box's entry rules",
    description:
      "Refused with `entry_denied` (`params.reason`: `not_a_member`, `outside_hours`, " <>
        "`no_booking_in_window`, `staff_only`), `choose_door` (`params.doors`) when the " <>
        "branch has several doors, `no_door_here`, or `door_offline` when the controller " <>
        "cannot be reached: the door stays locked and the member goes to the desk.",
    security: [%{"bearerAuth" => []}],
    request_body: S.body(S.open_request()),
    responses: [
      ok: {"Opened", "application/json", S.open_result()},
      forbidden: {"Entry refused", "application/json", S.error()},
      conflict: {"Choose a door", "application/json", S.error()},
      service_unavailable: {"The door controller is offline", "application/json", S.error()}
    ]
  )

  def open(conn, _params) do
    with {:ok, result} <- DoorAccess.open(GuardianPlug.current_resource(conn), conn.body_params),
         do: json(conn, result)
  end

  operation(:ingest,
    summary: "A door controller's own event (door opened, forced, held open); GET or POST",
    description:
      "The URL with its token is shown in the door's settings. An unknown door and a wrong " <>
        "token answer the same 404.",
    security: [],
    parameters: [
      %Parameter{name: :id, in: :path, required: true, schema: S.uuid()},
      %Parameter{
        name: :token,
        in: :query,
        required: true,
        schema: %Schema{type: :string, maxLength: 200}
      }
    ],
    request_body: %RequestBody{
      required: false,
      content: %{
        "application/json" => %MediaType{schema: %Schema{type: :object, additionalProperties: true}}
      }
    },
    responses: [ok: {"Recorded", "application/json", S.recorded()}]
  )

  # A Shelly action calls a URL with GET and query parameters (`event=…`);
  # Kisi posts JSON. Both arrive here.
  def ingest(conn, %{id: id, token: token}) do
    params = conn.query_params |> Map.delete("token") |> Map.merge(raw_body(conn.body_params))
    with {:ok, result} <- DoorAccess.ingest(id, token, params), do: json(conn, result)
  end

  defp raw_body(params) when is_map(params),
    do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end
