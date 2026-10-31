defmodule Palee.Automations.AutomationStore do
  @moduledoc "Facade over the automations adapter (ADR-346); every call runs in the box's scope."

  @behaviour Palee.Automations.Ports.AutomationStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :automation_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def list_automations(context), do: call(context, :list_automations, [])

  @impl true
  def get_automation(context, recipe), do: call(context, :get_automation, [recipe])

  @impl true
  def put_automation(context, recipe, attrs), do: call(context, :put_automation, [recipe, attrs])

  @impl true
  def enqueue(context, attrs), do: call(context, :enqueue, [attrs])

  @impl true
  def claim_due(context, now, limit, timeout),
    do: call(context, :claim_due, [now, limit, timeout])

  @impl true
  def finish(context, id, changes), do: call(context, :finish, [id, changes])

  @impl true
  def list_deliveries(context, filters), do: call(context, :list_deliveries, [filters])

  @impl true
  def delivery_stats(context, since), do: call(context, :delivery_stats, [since])

  @impl true
  def cancel_pending(context, filters), do: call(context, :cancel_pending, [filters])

  @impl true
  def get_preference(context, user_id), do: call(context, :get_preference, [user_id])

  @impl true
  def put_preference(context, user_id, attrs),
    do: call(context, :put_preference, [user_id, attrs])

  @impl true
  def birthdays(context, month, day), do: call(context, :birthdays, [month, day])
end
