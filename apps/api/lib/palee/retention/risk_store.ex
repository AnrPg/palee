defmodule Palee.Retention.RiskStore do
  @moduledoc "Facade over the risk adapter (ADR-347); every call runs in the box's scope."

  @behaviour Palee.Retention.Ports.RiskStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :retention_risk_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def all(context), do: call(context, :all, [])

  @impl true
  def get(context, user_id), do: call(context, :get, [user_id])

  @impl true
  def put(context, user_id, attrs), do: call(context, :put, [user_id, attrs])

  @impl true
  def delete_except(context, user_ids), do: call(context, :delete_except, [user_ids])

  @impl true
  def list(context, filters), do: call(context, :list, [filters])

  @impl true
  def level_counts(context), do: call(context, :level_counts, [])

  @impl true
  def add_action(context, user_id, attrs), do: call(context, :add_action, [user_id, attrs])

  @impl true
  def actions(context, user_id, limit), do: call(context, :actions, [user_id, limit])
end
