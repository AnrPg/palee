defmodule Palee.Infrastructure.Execution.EctoSplitStore do
  @moduledoc "Ecto adapter of the split marks port (ADR-374)."

  @behaviour Palee.Execution.Ports.SplitStore

  import Ecto.Query

  alias Palee.Execution.ExecutionSplit
  alias Palee.Repo

  @impl true
  def insert_splits(_execution_id, _user_id, [], _now), do: {:ok, 0}

  def insert_splits(execution_id, user_id, rows, now) do
    entries =
      Enum.map(rows, fn row ->
        row
        |> Map.take([:segment_index, :section_id, :section_ordinal, :phase, :round, :elapsed_ms])
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          execution_id: execution_id,
          user_id: user_id,
          inserted_at: now
        })
      end)

    {count, _rows} =
      Repo.insert_all(ExecutionSplit, entries,
        on_conflict: :nothing,
        conflict_target: [:execution_id, :segment_index, :round]
      )

    {:ok, count}
  end

  @impl true
  def list_splits([]), do: %{}

  def list_splits(execution_ids) do
    ExecutionSplit
    |> where([s], s.execution_id in ^execution_ids)
    |> order_by([s], asc: s.elapsed_ms, asc: s.segment_index, asc: s.round)
    |> Repo.all()
    |> Enum.group_by(& &1.execution_id)
  end
end
