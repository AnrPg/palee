defmodule Palee.Execution.Ports.SplitStore do
  @moduledoc """
  Persistence port of execution split marks (ADR-374). Calls run inside the
  caller's RepoContext: the owner writes; row security lets whoever may read
  the execution read its splits.
  """

  @type id :: Ecto.UUID.t()

  @doc "Stores new marks of one execution, ignoring ones it already has; returns how many were new."
  @callback insert_splits(execution_id :: id(), user_id :: id(), rows :: [map()], DateTime.t()) ::
              {:ok, non_neg_integer()}

  @doc "The marks of these executions, by execution id."
  @callback list_splits([id()]) :: %{id() => [Palee.Execution.ExecutionSplit.t()]}
end
