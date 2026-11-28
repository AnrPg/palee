defmodule Palee.Finance.PackageTermsStore do
  @moduledoc "ADR-770: dispatches to the configured `Palee.Finance.Ports.PackageTermsStore`."

  @behaviour Palee.Finance.Ports.PackageTermsStore

  defp adapter, do: Application.fetch_env!(:palee, :package_terms_store)

  @impl true
  def preview(package_id, params), do: adapter().preview(package_id, params)
  @impl true
  def update(package_id, params, choice, actor_id),
    do: adapter().update(package_id, params, choice, actor_id)

  @impl true
  def apply_due(subscription_id, on), do: adapter().apply_due(subscription_id, on)
  @impl true
  def apply_due_all(today), do: adapter().apply_due_all(today)
  @impl true
  def for_subscriptions(ids), do: adapter().for_subscriptions(ids)
end
