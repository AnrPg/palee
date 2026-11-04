defmodule Palee.Workouts.Ports.ExerciseCatalogStore do
  @moduledoc """
  ADR-461: the persisted half of the exercise catalog: the Palee team's
  approved additions, the candidates waiting for them and the audit trail.
  Platform data holding no person; the vendor console is its only writer of
  decisions.
  """

  @type addition :: %{
          kind: String.t(),
          catalog_slug: String.t(),
          label: String.t(),
          category: String.t() | nil
        }

  @callback additions() :: [addition()]

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
  Writes a decision in one transaction: the addition (if any), the candidate's
  status, and the audit event. Fails when the candidate is no longer pending.
  """
  @callback record_decision(
              candidate_id :: Ecto.UUID.t(),
              decision :: %{
                action: String.t(),
                catalog_slug: String.t() | nil,
                addition: map() | nil
              },
              actor_user_id :: Ecto.UUID.t(),
              metadata :: map(),
              DateTime.t()
            ) :: {:ok, map()} | {:error, term()}

  @callback audit_events(limit :: pos_integer()) :: [map()]
end
