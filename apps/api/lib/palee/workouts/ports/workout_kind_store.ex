defmodule Palee.Workouts.Ports.WorkoutKindStore do
  @moduledoc """
  ADR-690: a box's own workout types (tenant-scoped: the adapter reads and
  writes in the open tenant session), the kinds the Palee team added and the
  team's queue (platform data, no person).
  """

  @type kind :: %{
          id: Ecto.UUID.t(),
          ref: String.t(),
          label: String.t(),
          folded: String.t(),
          family: String.t(),
          status: String.t(),
          merged_into: String.t() | nil
        }

  @doc "The box's view of every kind: `%{additions, box}` (see `WorkoutKinds`)."
  @callback catalogue() :: %{additions: [map()], box: [kind()]}
  @callback additions() :: [%{key: String.t(), family: String.t(), labels: map()}]
  @callback list_box_kinds() :: [kind()]
  @callback get_box_kind(Ecto.UUID.t()) :: kind() | nil
  @callback find_box_kind_by_folded(String.t()) :: kind() | nil
  @callback insert_box_kind(map()) :: {:ok, kind()} | {:error, :workout_kind_exists}
  @callback update_box_kind(Ecto.UUID.t(), map()) ::
              {:ok, kind()} | {:error, :not_found | :workout_kind_exists}
  @doc "Marks a box type merged into `target_ref` and rewrites the box's WODs."
  @callback merge_box_kind(Ecto.UUID.t(), String.t()) ::
              {:ok, %{kind: kind(), workouts: non_neg_integer()}} | {:error, term()}
  @doc "Recomputes the families of the box's WODs with this type (its family changed)."
  @callback refresh_box_kind(Ecto.UUID.t()) :: non_neg_integer()
  @doc "Box types by id from any box, label and family only (readers across boxes)."
  @callback box_kinds_by_ids([Ecto.UUID.t()]) :: [map()]
  @callback box_kinds_with_folded(String.t()) :: [kind()]

  @callback note_box_kind_candidate(map(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, map()} | {:error, term()}
  @callback note_profile_suggestion(String.t(), String.t(), Ecto.UUID.t(), DateTime.t()) ::
              {:ok, map()} | {:error, term()}
  @callback list_candidates(String.t(), pos_integer()) :: [map()]
  @callback recently_decided(pos_integer()) :: [map()]
  @callback get_candidate(String.t()) :: map() | nil
  @callback record_decision(
              Ecto.UUID.t(),
              status :: String.t(),
              decision :: map(),
              addition :: map() | nil,
              actor_user_id :: Ecto.UUID.t(),
              DateTime.t()
            ) :: {:ok, map()} | {:error, term()}
  @callback undigested_candidates() :: [map()]
  @callback mark_digested([Ecto.UUID.t()], DateTime.t()) :: non_neg_integer()
end
