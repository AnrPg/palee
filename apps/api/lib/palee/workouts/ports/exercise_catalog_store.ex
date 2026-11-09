defmodule Palee.Workouts.Ports.ExerciseCatalogStore do
  @moduledoc """
  ADR-461: the persisted half of the exercise catalog: the Palee team's
  approved additions, the candidates waiting for them and the audit trail.
  Platform data holding no person; the vendor console is its only writer of
  decisions.
  """

  @doc "Counts typed names that matched nothing (`%{name, folded, new_owner?}`), seen at `now`."
  @callback note_candidates([map()], DateTime.t()) :: :ok

  @callback list_candidates(
              status :: String.t(),
              min_owners :: non_neg_integer(),
              limit :: pos_integer()
            ) ::
              [map()]

  @callback get_candidate(Ecto.UUID.t()) :: map() | nil

  @doc """
  Writes a decision in one transaction: the addition (if any) with its
  reference rows (ADR-560: an entry's exercise and `targets`, an alias's
  Quick Text alias), the candidate's status, and the audit event. Fails when the candidate is no longer pending.
  """
  @callback record_decision(
              candidate_id :: Ecto.UUID.t(),
              decision :: %{
                optional(:targets) => map() | nil,
                required(:action) => String.t(),
                required(:catalog_slug) => String.t() | nil,
                required(:addition) => map() | nil
              },
              actor_user_id :: Ecto.UUID.t(),
              metadata :: map(),
              DateTime.t()
            ) :: {:ok, map()} | {:error, term()}

  @doc """
  ADR-560: replaces an exercise's muscle and quality targets and records a
  `set_targets` audit event (before and after) in one transaction.
  """
  @callback replace_exercise_targets(
              exercise_id :: String.t(),
              targets :: %{muscles: [%{id: String.t(), role: atom()}], qualities: [String.t()]},
              actor_user_id :: Ecto.UUID.t(),
              DateTime.t()
            ) :: {:ok, map()} | {:error, term()}

  @callback audit_events(limit :: pos_integer()) :: [map()]
end
