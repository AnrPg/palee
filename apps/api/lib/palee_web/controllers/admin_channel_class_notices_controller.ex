defmodule PaleeWeb.AdminChannelClassNoticesController do
  @moduledoc """
  «Ενημέρωση συμμετεχόντων» from a class (ADR-385): the app first, SMS
  only for the participants the app cannot reach, priced before sending.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Channels.ClassNotices
  alias PaleeWeb.Schemas.Channels, as: C

  action_fallback PaleeWeb.FallbackController

  tags(["Channels"])
  security([%{"bearerAuth" => []}])

  plug PaleeWeb.Plugs.RateLimit,
       [max: 30, interval: 60_000, bucket: "channel-class-notice"] when action in [:create]

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:preview,
    summary: "Who would learn of a class notice, in the app or by SMS, and the SMS cost",
    description: "Nothing is sent. `channels_demo_mode` and the like come back as `sms_blocked`.",
    request_body: C.body(C.class_notice_body()),
    responses: [ok: {"Preview", "application/json", C.class_notice()}]
  )

  def preview(conn, _params) do
    with {:ok, summary} <- ClassNotices.preview(conn.assigns.tenant_context, conn.body_params) do
      json(conn, summary)
    end
  end

  operation(:create,
    summary: "Send a class notice: in the app to those with a device, by SMS to the rest",
    description: "`idempotency_key` is required: a repeated press sends nothing twice.",
    request_body: C.body(C.class_notice_body()),
    responses: [ok: {"Sent", "application/json", C.class_notice()}]
  )

  def create(conn, _params) do
    with {:ok, summary} <- ClassNotices.deliver(conn.assigns.tenant_context, conn.body_params) do
      json(conn, summary)
    end
  end
end
