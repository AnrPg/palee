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
  def claim_first_class(user_id, scheduled_class_id, today, now),
    do: adapter().claim_first_class(user_id, scheduled_class_id, today, now)

  @impl true
  def release_first_class(request_id), do: adapter().release_first_class(request_id)
  @impl true
  def first_class(user_id), do: adapter().first_class(user_id)
end
