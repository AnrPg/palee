defmodule PaleeWeb.PlatformChannelMarginsController do
  @moduledoc """
  ADR-369: Palee's margin on the messages it sends for boxes on its own
  provider account, and a box's monthly charge with the providers' cost.
  For the Palee team only (vendor console); the providers' cost is never
  shown to a box.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.Channels.ChannelMargins
  alias PaleeWeb.Schemas.Channels, as: C

  action_fallback PaleeWeb.FallbackController

  tags(["Platform"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "Palee's margin per channel on Palee-managed messages (basis points)",
    responses: [ok: {"Margins", "application/json", C.margins()}]
  )

  def show(conn, _params), do: json(conn, ChannelMargins.show())

  operation(:update,
    summary: "Set Palee's margin per channel; channels not sent keep theirs",
    request_body: C.body(C.margins_body()),
    responses: [ok: {"Margins", "application/json", C.margins()}]
  )

  def update(conn, _params) do
    with {:ok, result} <- ChannelMargins.save(conn.body_params, vendor_id(conn)) do
      json(conn, result)
    end
  end

  operation(:charges,
    summary: "What Palee charges a box for a month's messages, with the providers' cost",
    parameters: [
      id: [in: :path, type: %Schema{type: :string, format: :uuid}, required: true],
      month: [
        in: :query,
        type: %Schema{type: :string, pattern: "^[0-9]{4}-[0-9]{2}$"},
        description: "YYYY-MM on the box's clock; this month when left out"
      ]
    ],
    responses: [ok: {"Charge", "application/json", C.monthly_charge()}]
  )

  def charges(conn, %{id: id} = params) do
    with {:ok, charge} <- ChannelMargins.monthly_charge(id, Map.get(params, :month)) do
      json(conn, charge)
    end
  end

  defp vendor_id(conn), do: conn.assigns.platform_context.user_id
end
