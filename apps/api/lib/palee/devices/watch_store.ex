defmodule Palee.Devices.WatchStore do
  @moduledoc "Dispatches the watch persistence port to the configured adapter (ADR-375)."

  @behaviour Palee.Devices.Ports.WatchStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def list_links(user_id), do: adapter().list_links(user_id)
  @impl true
  def get_link(user_id, platform), do: adapter().get_link(user_id, platform)
  @impl true
  def save_link(link, attrs), do: adapter().save_link(link, attrs)
  @impl true
  def delete_link(user_id, platform), do: adapter().delete_link(user_id, platform)

  @impl true
  def insert_heart_rate(execution_id, user_id, rows, now),
    do: adapter().insert_heart_rate(execution_id, user_id, rows, now)

  @impl true
  def list_heart_rate(execution_id), do: adapter().list_heart_rate(execution_id)

  defp adapter, do: Application.fetch_env!(:palee, :watch_store)
end
