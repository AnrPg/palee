defmodule PaleeWeb.MyChannelsController do
  @moduledoc """
  The member's «Μηνύματα από το box» (ADR-350): their number for this box
  and which channels they agree to, for what.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Channels.MyChannels
  alias PaleeWeb.Schemas.Channels, as: C

  action_fallback PaleeWeb.FallbackController

  tags(["Channels"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "My number and consents for this box's SMS messages",
    responses: [ok: {"My channels", "application/json", C.my_channels()}]
  )

  def show(conn, _params), do: json(conn, MyChannels.show(conn.assigns.tenant_context))

  operation(:update,
    summary: "Save my number and language and give or withdraw consents",
    request_body: C.body(C.my_channels_body()),
    responses: [ok: {"My channels", "application/json", C.my_channels()}]
  )

  def update(conn, _params) do
    with {:ok, result} <- MyChannels.save(conn.assigns.tenant_context, conn.body_params) do
      json(conn, result)
    end
  end
end
