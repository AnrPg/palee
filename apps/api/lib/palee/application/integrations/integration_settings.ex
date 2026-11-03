defmodule Palee.Application.Integrations.IntegrationSettings do
  @moduledoc """
  Staff › Settings › «Συνδέσεις» (ADR-378..380): API keys, webhooks with
  their delivery log, and the email-list connection. Owners and admins
  (`manage_settings`) only.

  A key acts for the person who makes it, so it can never do more than
  they can; the scopes chosen here narrow it further.
  """

  alias Palee.Application.Integrations.{AudienceSync, WebhookDelivery}
  alias Palee.Integrations

  @doc "What the settings screen needs to offer: scopes and event types, EN and EL."
  def catalog,
    do: %{
      scopes: Integrations.scope_catalog(),
      events: Enum.map(Integrations.event_catalog(), &Map.drop(&1, [:source])),
      audience_providers: Integrations.audience_providers() -- sandbox_hidden()
    }

  defp sandbox_hidden,
    do: if(Application.get_env(:palee, :open_platform_sandbox, false), do: [], else: ["sandbox"])

  # ── API keys ────────────────────────────────────────────────────────────

  def list_keys(context), do: %{keys: Integrations.list_api_keys(context)}

  @doc "`{:ok, %{key, token}}`: the token is shown once."
  def create_key(context, params, now \\ DateTime.utc_now()) do
    Integrations.create_api_key(
      context,
      %{
        name: param(params, :name),
        scopes: param(params, :scopes),
        expires_at: param(params, :expires_at)
      },
      context.user_id,
      now
    )
  end

  def rotate_key(context, id, now \\ DateTime.utc_now()),
    do: Integrations.rotate_api_key(context, id, now)

  def revoke_key(context, id, now \\ DateTime.utc_now()),
    do: Integrations.revoke_api_key(context, id, context.user_id, now)

  # ── Webhooks ────────────────────────────────────────────────────────────

  def list_webhooks(context), do: %{webhooks: Integrations.list_endpoints(context)}

  @doc "`{:ok, %{endpoint, secret}}`: the signing secret is shown once."
  def create_webhook(context, params) do
    Integrations.create_endpoint(
      context,
      %{
        url: param(params, :url),
        events: param(params, :events),
        description: param(params, :description)
      },
      context.user_id
    )
  end

  def update_webhook(context, id, params) do
    changes =
      [:url, :events, :description, :status]
      |> Enum.flat_map(fn key ->
        case fetch(params, key) do
          {:ok, value} -> [{key, value}]
          :error -> []
        end
      end)
      |> Map.new()

    Integrations.update_endpoint(context, id, changes)
  end

  def delete_webhook(context, id), do: Integrations.delete_endpoint(context, id)

  def rotate_webhook_secret(context, id, now \\ DateTime.utc_now()),
    do: Integrations.rotate_endpoint_secret(context, id, now)

  @doc "«Δοκιμή»: a `ping` to the endpoint, sent now. `{:ok, delivery}`."
  def test_webhook(context, id, now \\ DateTime.utc_now()) do
    with {:ok, delivery} <- Integrations.enqueue_ping(context, id, Ecto.UUID.generate(), now) do
      send_now(context, delivery.id)
    end
  end

  def deliveries(context, webhook_id, params) do
    with {:ok, _endpoint} <- Integrations.get_endpoint(context, webhook_id) do
      filters =
        %{
          endpoint_id: webhook_id,
          status: param(params, :status),
          limit: param(params, :limit),
          offset: param(params, :offset)
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, Integrations.list_deliveries(context, filters)}
    end
  end

  def delivery(context, id), do: Integrations.get_delivery(context, id)

  @doc "Sends an event again (a new delivery with the same event id)."
  def replay(context, id, now \\ DateTime.utc_now()) do
    with {:ok, delivery} <- Integrations.replay(context, id, now),
         do: send_now(context, delivery.id)
  end

  defp send_now(context, delivery_id) do
    WebhookDelivery.schedule(context, delivery_id)
    Integrations.get_delivery(context, delivery_id)
  end

  # ── Email list (ADR-380) ────────────────────────────────────────────────

  def audience(context), do: %{connection: Integrations.connection(context)}

  @doc "Connects Mailchimp or Brevo after the provider accepted the key, then syncs."
  def save_audience(context, params, now \\ DateTime.utc_now()) do
    with {:ok, connection} <-
           Integrations.save_connection(
             context,
             %{
               provider: param(params, :provider),
               list_id: param(params, :list_id),
               api_key: param(params, :api_key)
             },
             context.user_id
           ) do
      sync_audience(context, now)
      {:ok, %{connection: connection}}
    end
  end

  def delete_audience(context), do: Integrations.delete_connection(context)

  @doc "«Συγχρονισμός τώρα»."
  def sync_audience(context, now \\ DateTime.utc_now()) do
    with :ok <- Integrations.request_sync(context, now), do: AudienceSync.schedule(context)
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp fetch(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(params, Atom.to_string(key))
    end
  end
end
