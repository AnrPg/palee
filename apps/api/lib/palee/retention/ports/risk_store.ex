defmodule Palee.Retention.Ports.RiskStore do
  @moduledoc "ADR-347: the latest risk of each box member. Every call runs in the box's scope."

  alias Palee.Retention.{Risk, RiskAction}

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @doc "Every stored risk of the box, by profile."
  @callback all(context()) :: %{id() => Risk.t()}

  @callback get(context(), id()) :: Risk.t() | nil

  @doc "Writes a profile's risk (insert or update in place)."
  @callback put(context(), id(), map()) :: {:ok, Risk.t()} | {:error, Ecto.Changeset.t()}

  @doc "Removes the risks (and their action logs) of profiles that are no longer box members."
  @callback delete_except(context(), [id()]) :: non_neg_integer()

  @doc """
  Risks at `levels`, highest score first; those snoozed past `today` are
  left out unless `include_snoozed`. `limit` at most 200.
  """
  @callback list(context(), %{
              required(:levels) => [String.t()],
              required(:today) => Date.t(),
              optional(:include_snoozed) => boolean(),
              optional(:limit) => pos_integer()
            }) :: [Risk.t()]

  @doc "How many members are at each level (snoozed ones included)."
  @callback level_counts(context()) :: %{String.t() => non_neg_integer()}

  @doc "ADR-384: logs what staff did about a member (`kind`, `actor_id`, `at`, …)."
  @callback add_action(context(), id(), map()) ::
              {:ok, RiskAction.t()} | {:error, Ecto.Changeset.t()}

  @doc "ADR-384: a member's action log, newest first, at most `limit` (≤ 100)."
  @callback actions(context(), id(), pos_integer()) :: [RiskAction.t()]
end
