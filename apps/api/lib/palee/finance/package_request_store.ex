defmodule Palee.Finance.PackageRequestStore do
  @moduledoc "ADR-291: dispatches to the configured `Palee.Finance.Ports.PackageRequestStore`."

  @behaviour Palee.Finance.Ports.PackageRequestStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :package_request_store)

  @doc "Runs `fun` inside the tenant scope of `context`."
  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  @impl true
  def request(params), do: adapter().request(params)
  @impl true
  def get(id), do: adapter().get(id)
  @impl true
  def list_open(today, opts \\ []), do: adapter().list_open(today, opts)
  @impl true
  def close(id, status, params), do: adapter().close(id, status, params)
  @impl true
  def lapse_before(today, now), do: adapter().lapse_before(today, now)
  @impl true
  def fulfil_answered(now), do: adapter().fulfil_answered(now)
  @impl true
  def claim_wait_booking(user_id, scheduled_class_id, allowed, today, now),
    do: adapter().claim_wait_booking(user_id, scheduled_class_id, allowed, today, now)

  @impl true
  def release_wait_booking(wait_booking_id), do: adapter().release_wait_booking(wait_booking_id)
  @impl true
  def wait_bookings_used(user_id), do: adapter().wait_bookings_used(user_id)
  @impl true
  def wait_bookings_used_by(user_ids), do: adapter().wait_bookings_used_by(user_ids)
end
