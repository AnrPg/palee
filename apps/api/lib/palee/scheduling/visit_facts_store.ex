defmodule Palee.Scheduling.VisitFactsStore do
  @moduledoc false
  @behaviour Palee.Scheduling.Ports.VisitFactsStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :visit_facts_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def visit_counts(context, user_ids, before, class_type_id, exclude_class_ids),
    do: tenant_call(context, :visit_counts, [user_ids, before, class_type_id, exclude_class_ids])

  @impl true
  def referrals(context, user_ids), do: tenant_call(context, :referrals, [user_ids])
end
