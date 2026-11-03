defmodule Palee.Workouts.Ports.WorkoutSnapshotStore do
  @moduledoc "ADR-357: storage of WOD snapshots and the rows that point at them."

  @type snapshot :: %{
          id: Ecto.UUID.t(),
          master_workout_id: Ecto.UUID.t(),
          content_hash: String.t(),
          format_version: pos_integer(),
          title: String.t() | nil,
          content: map(),
          inserted_at: DateTime.t()
        }

  @type holder :: :assignment | :execution | :training_log

  @doc "Stores the snapshot, or returns the one with the same content (idempotent)."
  @callback put_snapshot(map(), Ecto.UUID.t(), map()) :: {:ok, snapshot()} | {:error, term()}
  @callback get_snapshot(map(), Ecto.UUID.t()) :: snapshot() | nil
  @callback list_for_workout(map(), Ecto.UUID.t()) :: [snapshot()]
  @doc "Points an assignment, execution or training log entry at a snapshot."
  @callback attach(map(), holder(), Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, :not_found}
  @doc "The snapshot id a holder points at, if any."
  @callback snapshot_id_of(map(), holder(), Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  @doc "Whether one of the person's own assignments, runs or scores points at the snapshot."
  @callback referenced_by?(map(), Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  @doc """
  ADR-389: the snapshot id of the person's own run or score (`nil` before
  ADR-357), or `{:error, :not_found}` when the holder is not theirs.
  """
  @callback own_snapshot_id(map(), :execution | :training_log, Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, Ecto.UUID.t() | nil} | {:error, :not_found}

  @typedoc "ADR-393: one run or score of a WOD that points at a snapshot."
  @type performed :: %{
          user_id: Ecto.UUID.t(),
          holder: :execution | :training_log,
          holder_id: Ecto.UUID.t(),
          content_hash: String.t(),
          at: DateTime.t() | nil
        }

  @doc """
  ADR-393: every finished run and every score still standing (not voided) of
  the WOD that points at one of its snapshots, with that snapshot's hash.
  """
  @callback list_performed(map(), Ecto.UUID.t()) :: [performed()]
end
