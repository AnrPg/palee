defmodule PaleeWeb.AdminChannelMessagesController do
  @moduledoc """
  Staff › «Μηνύματα SMS» (ADR-348/351): preview and send a message to a
  member or lead, the sent messages with their state and cost, send a
  failed one again, stop a queued one.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.Channels.ChannelMessages
  alias PaleeWeb.Schemas.Channels, as: C

  action_fallback PaleeWeb.FallbackController

  tags(["Channels"])
  security([%{"bearerAuth" => []}])

  plug PaleeWeb.Plugs.RateLimit,
       [max: 60, interval: 60_000, bucket: "channel-send"] when action in [:create, :preview]

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id [id: [in: :path, type: %Schema{type: :string, format: :uuid}, required: true]]

  operation(:index,
    summary: "Sent and waiting messages, newest first",
    parameters: [
      status: [in: :query, type: %Schema{type: :string}],
      channel: [in: :query, type: %Schema{type: :string}],
      contact_id: [in: :query, type: %Schema{type: :string, format: :uuid}],
      source_ref: [in: :query, type: %Schema{type: :string, maxLength: 120}],
      limit: [in: :query, type: %Schema{type: :integer, minimum: 1, maximum: 200}],
      offset: [in: :query, type: %Schema{type: :integer, minimum: 0}]
    ],
    responses: [ok: {"Messages", "application/json", C.messages()}]
  )

  def index(conn, params), do: json(conn, ChannelMessages.list(conn.assigns.tenant_context, params))

  operation(:show,
    summary: "One message with its attempts and delivery receipts",
    parameters: @id,
    responses: [ok: {"Message", "application/json", C.message()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, message} <- ChannelMessages.show(conn.assigns.tenant_context, id) do
      json(conn, message)
    end
  end

  operation(:preview,
    summary: "What a message would be: channel, text, parts, cost, when it leaves, budget",
    description:
      "Nothing is queued. Same errors as sending: `channels_not_connected`, " <>
        "`channel_contact_missing`, `channel_consent_missing`, `channel_opted_out`, " <>
        "`channel_budget_exceeded`, `channel_template_missing`…",
    request_body: C.body(C.send_body()),
    responses: [ok: {"Preview", "application/json", C.preview()}]
  )

  def preview(conn, _params) do
    with {:ok, plan} <- ChannelMessages.preview(conn.assigns.tenant_context, conn.body_params) do
      json(conn, plan)
    end
  end

  operation(:create,
    summary: "Send a message to a member or lead by SMS (or another channel they agreed to)",
    description:
      "Queued in the outbox: quiet hours hold it unless `urgent` (service only). " <>
        "`idempotency_key` makes a repeated click answer the same message.",
    request_body: C.body(C.send_body()),
    responses: [created: {"Queued", "application/json", C.queued()}]
  )

  def create(conn, _params) do
    with {:ok, queued} <- ChannelMessages.send(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(queued)
    end
  end

  operation(:retry,
    summary: "Send a failed message again",
    parameters: @id,
    responses: [ok: {"Message", "application/json", C.message()}]
  )

  def retry(conn, %{id: id}) do
    with {:ok, message} <- ChannelMessages.retry(conn.assigns.tenant_context, id) do
      json(conn, message)
    end
  end

  operation(:cancel,
    summary: "Stop a message that has not left yet",
    parameters: @id,
    responses: [ok: {"Message", "application/json", C.message()}]
  )

  def cancel(conn, %{id: id}) do
    with {:ok, message} <- ChannelMessages.cancel(conn.assigns.tenant_context, id) do
      json(conn, message)
    end
  end
end
