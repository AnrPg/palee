defmodule PaleeWeb.AdminChannelSettingsController do
  @moduledoc """
  Staff › Ρυθμίσεις › «Μηνύματα SMS» (ADR-348..350): the provider
  connection, «Δοκιμή σύνδεσης», the month's cost against the budget cap,
  quiet hours and the wording of messages.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.Channels.ChannelSettings
  alias PaleeWeb.Schemas.Channels, as: C

  action_fallback PaleeWeb.FallbackController

  tags(["Channels"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "The SMS/Viber/WhatsApp provider, the providers on offer and this month's cost",
    responses: [ok: {"Settings", "application/json", C.settings()}]
  )

  def show(conn, _params), do: json(conn, ChannelSettings.show(conn.assigns.tenant_context))

  operation(:save,
    summary: "Connect the box's messaging provider, then check it",
    description:
      "`account_mode` `palee` (default) sends through Palee's own Brevo account, with the " <>
        "box's cost tracked against `monthly_budget_cents`; `own` uses the box's own Brevo API " <>
        "key (`secret`, kept when not sent, never returned). `quiet_start`/`quiet_end` " <>
        "(\"HH:MM\" on the box's clock, both null for none) hold non-urgent messages. " <>
        "`rotate_webhook` draws a new webhook URL.",
    request_body: C.body(C.settings_body()),
    responses: [ok: {"Connection", "application/json", C.settings_result()}]
  )

  def save(conn, _params) do
    with {:ok, result} <- ChannelSettings.save(conn.assigns.tenant_context, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:check,
    summary: "«Δοκιμή σύνδεσης»: ask the provider something harmless with the saved credentials",
    responses: [ok: {"Connection", "application/json", C.settings_result()}]
  )

  def check(conn, _params) do
    with {:ok, result} <- ChannelSettings.check(conn.assigns.tenant_context) do
      json(conn, result)
    end
  end

  operation(:usage,
    summary: "Messages and cost of a month (the box's clock) against the budget cap",
    parameters: [
      month: [
        in: :query,
        type: %Schema{type: :string, pattern: "^[0-9]{4}-[0-9]{2}$"},
        description: "YYYY-MM; this month when left out"
      ]
    ],
    responses: [ok: {"Usage", "application/json", C.usage()}]
  )

  def usage(conn, params) do
    with {:ok, usage} <- ChannelSettings.usage(conn.assigns.tenant_context, params) do
      json(conn, usage)
    end
  end

  operation(:templates,
    summary: "Palee's message wording and the box's own, per language",
    responses: [ok: {"Templates", "application/json", C.templates()}]
  )

  def templates(conn, _params),
    do: json(conn, ChannelSettings.templates(conn.assigns.tenant_context))

  operation(:save_template,
    summary: "Write the box's own wording of a message in one language",
    description:
      "Placeholders are `{{name}}`. Channel `whatsapp` rows carry the provider's template id " <>
        "and whether Meta approved it; WhatsApp only sends approved templates.",
    parameters: [key: [in: :path, type: %Schema{type: :string, maxLength: 60}, required: true]],
    request_body: C.body(C.template_body()),
    responses: [ok: {"Template", "application/json", C.template_row()}]
  )

  def save_template(conn, %{key: key}) do
    with {:ok, row} <-
           ChannelSettings.save_template(conn.assigns.tenant_context, key, conn.body_params) do
      json(conn, row)
    end
  end

  operation(:delete_template,
    summary: "Go back to Palee's wording for a message in one language",
    parameters: [
      key: [in: :path, type: %Schema{type: :string, maxLength: 60}, required: true],
      locale: [in: :query, type: %Schema{type: :string, maxLength: 10}, required: true],
      channel: [in: :query, type: %Schema{type: :string, enum: ["any", "whatsapp"]}]
    ],
    responses: [no_content: "Deleted"]
  )

  def delete_template(conn, %{key: key} = params) do
    :ok = ChannelSettings.delete_template(conn.assigns.tenant_context, key, params)
    send_resp(conn, :no_content, "")
  end
end
