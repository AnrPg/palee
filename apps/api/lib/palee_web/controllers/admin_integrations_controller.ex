defmodule PaleeWeb.AdminIntegrationsController do
  @moduledoc """
  Staff › Settings › «Συνδέσεις» (ADR-378..380): public API keys, webhooks
  with their delivery log, and the box's email list (Mailchimp or Brevo).
  Owners and admins (`manage_settings`). Secrets (a key's token, a
  webhook's signing secret) are answered once, when made or rotated.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Integrations.IntegrationSettings
  alias PaleeWeb.Schemas.OpenPlatform, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Integrations"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:catalog,
    summary: "Scopes, webhook events and email list providers the settings can offer (EN, EL)",
    responses: [ok: {"Catalog", "application/json", S.catalog()}]
  )

  def catalog(conn, _params), do: json(conn, IntegrationSettings.catalog())

  # ── API keys ────────────────────────────────────────────────────────────

  operation(:keys,
    summary: "The box's public API keys (never their secrets)",
    responses: [ok: {"Keys", "application/json", S.api_keys()}]
  )

  def keys(conn, _params), do: json(conn, IntegrationSettings.list_keys(ctx(conn)))

  operation(:create_key,
    summary: "Make an API key that acts for you, narrowed to the chosen scopes",
    description:
      "The token is answered once. The key can never do more than the person who made " <>
        "it can do now; when they leave or lose the role, the key stops working.",
    request_body: S.body(S.api_key_body()),
    responses: [created: {"Key and token", "application/json", S.api_key_secret()}]
  )

  def create_key(conn, _params) do
    with {:ok, result} <- IntegrationSettings.create_key(ctx(conn), conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:rotate_key,
    summary: "Rotate a key's secret; the old one keeps working for 24 hours",
    parameters: [@id],
    responses: [ok: {"Key and new token", "application/json", S.api_key_secret()}]
  )

  def rotate_key(conn, %{id: id}) do
    with {:ok, result} <- IntegrationSettings.rotate_key(ctx(conn), id), do: json(conn, result)
  end

  operation(:revoke_key,
    summary: "Revoke a key at once (its webhook subscriptions go with it)",
    parameters: [@id],
    responses: [ok: {"Key", "application/json", S.one(:key, S.api_key())}]
  )

  def revoke_key(conn, %{id: id}) do
    with {:ok, key} <- IntegrationSettings.revoke_key(ctx(conn), id), do: json(conn, %{key: key})
  end

  # ── Webhooks ────────────────────────────────────────────────────────────

  operation(:webhooks,
    summary: "The box's webhook endpoints",
    responses: [ok: {"Endpoints", "application/json", S.webhooks()}]
  )

  def webhooks(conn, _params), do: json(conn, IntegrationSettings.list_webhooks(ctx(conn)))

  operation(:create_webhook,
    summary: "Add a webhook endpoint (https); its signing secret is answered once",
    request_body: S.body(S.webhook_body()),
    responses: [created: {"Endpoint and secret", "application/json", S.webhook_secret()}]
  )

  def create_webhook(conn, _params) do
    with {:ok, result} <- IntegrationSettings.create_webhook(ctx(conn), conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:update_webhook,
    summary: "Change an endpoint's address, events or description, or turn it on or off",
    parameters: [@id],
    request_body: S.body(S.webhook_update_body()),
    responses: [ok: {"Endpoint", "application/json", S.one(:endpoint, S.webhook())}]
  )

  def update_webhook(conn, %{id: id}) do
    with {:ok, endpoint} <- IntegrationSettings.update_webhook(ctx(conn), id, conn.body_params),
         do: json(conn, %{endpoint: endpoint})
  end

  operation(:delete_webhook,
    summary: "Remove an endpoint and its delivery log",
    parameters: [@id],
    responses: [ok: {"Removed", "application/json", S.ok()}]
  )

  def delete_webhook(conn, %{id: id}) do
    with :ok <- ok(IntegrationSettings.delete_webhook(ctx(conn), id)), do: json(conn, %{ok: true})
  end

  operation(:rotate_webhook_secret,
    summary: "New signing secret; for 24 hours deliveries are signed with both",
    parameters: [@id],
    responses: [ok: {"Endpoint and secret", "application/json", S.webhook_secret()}]
  )

  def rotate_webhook_secret(conn, %{id: id}) do
    with {:ok, result} <- IntegrationSettings.rotate_webhook_secret(ctx(conn), id),
         do: json(conn, result)
  end

  operation(:test_webhook,
    summary: "Send a `ping` event to the endpoint now",
    parameters: [@id],
    responses: [ok: {"Delivery", "application/json", S.one(:delivery, S.delivery())}]
  )

  def test_webhook(conn, %{id: id}) do
    with {:ok, delivery} <- IntegrationSettings.test_webhook(ctx(conn), id),
         do: json(conn, %{delivery: delivery})
  end

  operation(:deliveries,
    summary: "An endpoint's delivery log, newest first",
    parameters: [
      @id,
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ~w(pending succeeded failed)}
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100}
      },
      %Parameter{
        name: :offset,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0}
      }
    ],
    responses: [ok: {"Deliveries", "application/json", S.deliveries()}]
  )

  def deliveries(conn, %{id: id} = params) do
    with {:ok, page} <- IntegrationSettings.deliveries(ctx(conn), id, Map.delete(params, :id)),
         do: json(conn, page)
  end

  operation(:delivery,
    summary: "One delivery with its payload and every attempt",
    parameters: [@id],
    responses: [ok: {"Delivery", "application/json", S.one(:delivery, S.delivery())}]
  )

  def delivery(conn, %{id: id}) do
    with {:ok, delivery} <- IntegrationSettings.delivery(ctx(conn), id),
         do: json(conn, %{delivery: delivery})
  end

  operation(:replay,
    summary: "Send a delivery's event again (same event id, a new delivery)",
    parameters: [@id],
    responses: [ok: {"Delivery", "application/json", S.one(:delivery, S.delivery())}]
  )

  def replay(conn, %{id: id}) do
    with {:ok, delivery} <- IntegrationSettings.replay(ctx(conn), id),
         do: json(conn, %{delivery: delivery})
  end

  # ── Email list ──────────────────────────────────────────────────────────

  operation(:audience,
    summary: "The box's email list connection (never its key)",
    responses: [ok: {"Connection", "application/json", S.audience()}]
  )

  def audience(conn, _params), do: json(conn, IntegrationSettings.audience(ctx(conn)))

  operation(:save_audience,
    summary: "Connect Mailchimp or Brevo; only members who said yes are sent",
    description:
      "The provider is asked first; a refused key or unknown list is not saved. A sync " <>
        "follows: members with marketing consent are subscribed, others unsubscribed.",
    request_body: S.body(S.audience_body()),
    responses: [ok: {"Connection", "application/json", S.audience()}]
  )

  def save_audience(conn, _params) do
    with {:ok, result} <- IntegrationSettings.save_audience(ctx(conn), conn.body_params),
         do: json(conn, result)
  end

  operation(:delete_audience,
    summary: "Disconnect the email list (the list itself is left as it is)",
    responses: [ok: {"Removed", "application/json", S.ok()}]
  )

  def delete_audience(conn, _params) do
    with :ok <- ok(IntegrationSettings.delete_audience(ctx(conn))), do: json(conn, %{ok: true})
  end

  operation(:sync_audience,
    summary: "Sync the email list now",
    responses: [ok: {"Requested", "application/json", S.ok()}]
  )

  def sync_audience(conn, _params) do
    with :ok <- ok(IntegrationSettings.sync_audience(ctx(conn))), do: json(conn, %{ok: true})
  end

  operation(:rotate_unsubscribe_url,
    summary: "A new address for Mailchimp's or Brevo's unsubscribe webhook (shown once)",
    description:
      "Paste it into the provider's webhook settings (Mailchimp: «Unsubscribes»; Brevo: " <>
        "marketing event «Unsubscribed»). Someone who unsubscribes there has their switch " <>
        "in Palee turned off too. The old address stops working at once.",
    responses: [ok: {"Address", "application/json", S.unsubscribe_url()}]
  )

  def rotate_unsubscribe_url(conn, _params) do
    with {:ok, result} <- IntegrationSettings.rotate_unsubscribe_url(ctx(conn)),
         do: json(conn, result)
  end

  defp ctx(conn), do: conn.assigns.tenant_context

  defp ok(:ok), do: :ok
  defp ok({:ok, _value}), do: :ok
  defp ok({:error, _reason} = error), do: error
end
