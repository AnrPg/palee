defmodule PaleeWeb.AdminChannelContactsController do
  @moduledoc """
  Staff › a member's or lead's card › «Τηλέφωνο για μηνύματα» (ADR-348 §4,
  ADR-350): the number (masked), language and consent per channel.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.Channels.ChannelContacts
  alias PaleeWeb.Schemas.Channels, as: C

  action_fallback PaleeWeb.FallbackController

  tags(["Channels"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "Contacts of several members or leads",
    parameters: [
      user_ids: [in: :query, type: %Schema{type: :string}, description: "Comma-separated ids"],
      lead_ids: [in: :query, type: %Schema{type: :string}, description: "Comma-separated ids"]
    ],
    responses: [ok: {"Contacts", "application/json", C.contacts()}]
  )

  def index(conn, params),
    do: json(conn, ChannelContacts.list(conn.assigns.tenant_context, params))

  operation(:lookup,
    summary: "The contact of one member (`user_id`) or lead (`lead_id`), or null",
    parameters: [
      user_id: [in: :query, type: %Schema{type: :string, format: :uuid}],
      lead_id: [in: :query, type: %Schema{type: :string, format: :uuid}]
    ],
    responses: [ok: {"Contact", "application/json", C.contact_result()}]
  )

  def lookup(conn, params) do
    with {:ok, result} <- ChannelContacts.show(conn.assigns.tenant_context, params) do
      json(conn, result)
    end
  end

  operation(:save,
    summary: "Save a member's or lead's mobile number and language",
    description: "The number is normalised to E.164 with the box's country; it must be a mobile.",
    request_body: C.body(C.contact_body()),
    responses: [ok: {"Contact", "application/json", C.contact_result()}]
  )

  def save(conn, _params) do
    with {:ok, result} <- ChannelContacts.save(conn.assigns.tenant_context, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:consent,
    summary: "Record a consent the person gave (or withdrew) for one channel and purpose",
    parameters: [id: [in: :path, type: %Schema{type: :string, format: :uuid}, required: true]],
    request_body: C.body(C.consent_body()),
    responses: [ok: {"Contact", "application/json", C.contact_result()}]
  )

  def consent(conn, %{id: id}) do
    with {:ok, result} <-
           ChannelContacts.set_consent(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:delete,
    summary: "Forget a contact with its consents and messages",
    parameters: [id: [in: :path, type: %Schema{type: :string, format: :uuid}, required: true]],
    responses: [no_content: "Deleted"]
  )

  def delete(conn, %{id: id}) do
    with :ok <- ChannelContacts.delete(conn.assigns.tenant_context, id) do
      send_resp(conn, :no_content, "")
    end
  end
end
