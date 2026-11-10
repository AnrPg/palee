defmodule Palee.Organizations.JoinRequestStore do
  @moduledoc "ADR-552: dispatches to the configured `Palee.Organizations.Ports.JoinRequestStore`."

  @behaviour Palee.Organizations.Ports.JoinRequestStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :join_request_store)

  @doc "Runs `fun` inside the scope of `context` (`organization_id`, `user_id`)."
  def with_scope(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def ask(user_id), do: adapter().ask(user_id)
  @impl true
  def get(id), do: adapter().get(id)
  @impl true
  def latest_for(user_id), do: adapter().latest_for(user_id)
  @impl true
  def list_open, do: adapter().list_open()
  @impl true
  def open_organization_ids(user_id, organization_ids),
    do: adapter().open_organization_ids(user_id, organization_ids)

  @impl true
  def close(id, params), do: adapter().close(id, params)
end
