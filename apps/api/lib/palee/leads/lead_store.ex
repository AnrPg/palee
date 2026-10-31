defmodule Palee.Leads.LeadStore do
  @moduledoc "Facade over the leads adapter (ADR-344); every call runs in the caller's box scope."

  @behaviour Palee.Leads.Ports.LeadStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :lead_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def transaction(context, fun), do: call(context, :transaction, [fun])

  @impl true
  def insert(context, attrs), do: call(context, :insert, [attrs])

  @impl true
  def update(context, lead, changes), do: call(context, :update, [lead, changes])

  @impl true
  def get(context, id), do: call(context, :get, [id])

  @impl true
  def get_for_update(context, id), do: call(context, :get_for_update, [id])

  @impl true
  def get_by_source_ref(context, source, ref),
    do: call(context, :get_by_source_ref, [source, ref])

  @impl true
  def find_by_email(context, email), do: call(context, :find_by_email, [email])

  @impl true
  def open_for_person(context, user_id, email),
    do: call(context, :open_for_person, [user_id, email])

  @impl true
  def list(context, filters), do: call(context, :list, [filters])

  @impl true
  def stage_counts(context), do: call(context, :stage_counts, [])

  @impl true
  def delete(context, id), do: call(context, :delete, [id])

  @impl true
  def add_event(context, attrs), do: call(context, :add_event, [attrs])

  @impl true
  def events(context, lead_id), do: call(context, :events, [lead_id])

  @impl true
  def insert_task(context, attrs), do: call(context, :insert_task, [attrs])

  @impl true
  def get_task(context, id), do: call(context, :get_task, [id])

  @impl true
  def complete_task(context, task, changes), do: call(context, :complete_task, [task, changes])

  @impl true
  def tasks(context, lead_id), do: call(context, :tasks, [lead_id])

  @impl true
  def open_tasks(context, filters), do: call(context, :open_tasks, [filters])

  @impl true
  def next_tasks(context, lead_ids), do: call(context, :next_tasks, [lead_ids])

  @impl true
  def purge_stale(context, cutoff), do: call(context, :purge_stale, [cutoff])
end
