defmodule Palee.Integrations.IntegrationStore do
  @moduledoc false
  @behaviour Palee.Integrations.Ports.IntegrationStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :integration_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def transaction(context, fun), do: tenant_call(context, :transaction, [fun])

  @impl true
  def lookup_api_key(prefix), do: adapter().lookup_api_key(prefix)
  @impl true
  def insert_api_key(context, attrs), do: tenant_call(context, :insert_api_key, [attrs])
  @impl true
  def list_api_keys(context), do: tenant_call(context, :list_api_keys, [])
  @impl true
  def get_api_key(context, id), do: tenant_call(context, :get_api_key, [id])
  @impl true
  def update_api_key(context, id, changes),
    do: tenant_call(context, :update_api_key, [id, changes])

  @impl true
  def touch_api_key(context, id, now), do: tenant_call(context, :touch_api_key, [id, now])

  @impl true
  def start_idempotent(context, attrs), do: tenant_call(context, :start_idempotent, [attrs])
  @impl true
  def finish_idempotent(context, id, status, body),
    do: tenant_call(context, :finish_idempotent, [id, status, body])

  @impl true
  def forget_idempotent(context, id), do: tenant_call(context, :forget_idempotent, [id])
  @impl true
  def purge_idempotency(context, now), do: tenant_call(context, :purge_idempotency, [now])

  @impl true
  def insert_endpoint(context, attrs), do: tenant_call(context, :insert_endpoint, [attrs])
  @impl true
  def list_endpoints(context, filters), do: tenant_call(context, :list_endpoints, [filters])
  @impl true
  def get_endpoint(context, id), do: tenant_call(context, :get_endpoint, [id])
  @impl true
  def update_endpoint(context, id, changes),
    do: tenant_call(context, :update_endpoint, [id, changes])

  @impl true
  def delete_endpoint(context, id), do: tenant_call(context, :delete_endpoint, [id])
  @impl true
  def subscribed_endpoints(context, type),
    do: tenant_call(context, :subscribed_endpoints, [type])

  @impl true
  def insert_deliveries(context, rows), do: tenant_call(context, :insert_deliveries, [rows])
  @impl true
  def claim_deliveries(context, which, now, limit),
    do: tenant_call(context, :claim_deliveries, [which, now, limit])

  @impl true
  def update_delivery(context, id, changes),
    do: tenant_call(context, :update_delivery, [id, changes])

  @impl true
  def record_attempt(context, attrs), do: tenant_call(context, :record_attempt, [attrs])
  @impl true
  def list_deliveries(context, filters), do: tenant_call(context, :list_deliveries, [filters])
  @impl true
  def get_delivery(context, id), do: tenant_call(context, :get_delivery, [id])
  @impl true
  def due_organizations(now), do: adapter().due_organizations(now)

  @impl true
  def lookup_connection(id), do: adapter().lookup_connection(id)
  @impl true
  def get_connection(context), do: tenant_call(context, :get_connection, [])
  @impl true
  def save_connection(context, attrs), do: tenant_call(context, :save_connection, [attrs])
  @impl true
  def delete_connection(context), do: tenant_call(context, :delete_connection, [])
  @impl true
  def claim_connection(context, now), do: tenant_call(context, :claim_connection, [now])
  @impl true
  def get_consent(context, user_id), do: tenant_call(context, :get_consent, [user_id])
  @impl true
  def put_consent(context, user_id, attrs),
    do: tenant_call(context, :put_consent, [user_id, attrs])

  @impl true
  def consented_user_ids(context), do: tenant_call(context, :consented_user_ids, [])
  @impl true
  def list_audience_members(context, connection_id),
    do: tenant_call(context, :list_audience_members, [connection_id])

  @impl true
  def upsert_audience_member(context, attrs),
    do: tenant_call(context, :upsert_audience_member, [attrs])

  @impl true
  def find_audience_member(context, connection_id, email_hash),
    do: tenant_call(context, :find_audience_member, [connection_id, email_hash])
end
