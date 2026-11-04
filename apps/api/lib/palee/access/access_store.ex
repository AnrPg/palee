defmodule Palee.Access.AccessStore do
  @moduledoc false
  @behaviour Palee.Access.Ports.AccessStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :access_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def lookup_door(id), do: adapter().lookup_door(id)
  @impl true
  def list_doors(context, filters), do: tenant_call(context, :list_doors, [filters])
  @impl true
  def get_door(context, id), do: tenant_call(context, :get_door, [id])
  @impl true
  def insert_door(context, attrs), do: tenant_call(context, :insert_door, [attrs])
  @impl true
  def update_door(context, id, changes), do: tenant_call(context, :update_door, [id, changes])
  @impl true
  def delete_door(context, id), do: tenant_call(context, :delete_door, [id])
  @impl true
  def insert_event(context, attrs), do: tenant_call(context, :insert_event, [attrs])
  @impl true
  def list_events(context, filters), do: tenant_call(context, :list_events, [filters])
  @impl true
  def purge_events(context, before), do: tenant_call(context, :purge_events, [before])
end
