defmodule PaleeWeb.AdminChannelEmailController do
  @moduledoc """
  Staff › Ρυθμίσεις › «Δικός μου πάροχος email» (ADR-368), the advanced
  option: by default Palee sends the box's email. The box's own SMTP
  provider, «Δοκιμή σύνδεσης» and the DNS records to set. The password is
  never returned.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Channels.ChannelEmailSettings
  alias PaleeWeb.Schemas.Channels, as: C

  action_fallback PaleeWeb.FallbackController

  tags(["Channels"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "The box's own email provider (null: Palee sends), the options and the DNS guide",
    responses: [ok: {"Email provider", "application/json", C.email_settings()}]
  )

  def show(conn, _params), do: json(conn, ChannelEmailSettings.show(conn.assigns.tenant_context))

  operation(:save,
    summary: "Connect the box's own email provider over SMTP",
    description:
      "Every email provider speaks SMTP. `secret` (the password) is kept when not sent and " <>
        "never returned. A change to the host, port, TLS mode, user name or password needs " <>
        "«Δοκιμή σύνδεσης» before the box's email goes through it. Platform email " <>
        "(verification, password reset, security notices) always goes through Palee.",
    request_body: C.body(C.email_settings_body()),
    responses: [ok: {"Email provider", "application/json", C.email_settings()}]
  )

  def save(conn, _params) do
    with {:ok, result} <-
           ChannelEmailSettings.save(conn.assigns.tenant_context, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:check,
    summary: "«Δοκιμή σύνδεσης»: connect, start TLS and log in, then quit; nothing is sent",
    responses: [ok: {"Check", "application/json", C.email_check_result()}]
  )

  def check(conn, _params) do
    with {:ok, result} <- ChannelEmailSettings.check(conn.assigns.tenant_context) do
      json(conn, result)
    end
  end

  operation(:delete,
    summary: "Remove the box's own email provider: Palee sends the box's email again",
    responses: [no_content: "Removed"]
  )

  def delete(conn, _params) do
    :ok = ChannelEmailSettings.delete(conn.assigns.tenant_context)
    send_resp(conn, :no_content, "")
  end
end
