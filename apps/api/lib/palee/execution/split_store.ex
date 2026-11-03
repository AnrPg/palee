defmodule Palee.Execution.SplitStore do
  @moduledoc "Dispatches the split marks port to the configured adapter (ADR-374)."

  @behaviour Palee.Execution.Ports.SplitStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def insert_splits(execution_id, user_id, rows, now),
    do: adapter().insert_splits(execution_id, user_id, rows, now)

  @impl true
  def list_splits(execution_ids), do: adapter().list_splits(execution_ids)

  defp adapter, do: Application.fetch_env!(:palee, :execution_split_store)
end
