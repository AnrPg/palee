defmodule Palee.Finance.Ports.PackageTermsStore do
  @moduledoc """
  ADR-770: where package changes reach the members who already hold the
  package. Every call runs inside the caller's tenant scope.
  """

  @typedoc "`apply_to`: `\"active\"` or `\"new_only\"`; nil when staff did not choose."
  @type choice :: %{apply_to: String.t() | nil, excluded_subscription_ids: [Ecto.UUID.t()]}

  @doc """
  What saving `params` on the package would do to its holders, without
  saving: `%{holders_count, needs_choice, changes, holders, earliest_next_on}`.
  """
  @callback preview(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Saves the package and, with `apply_to: "active"`, gives the holders the
  change (now or from their next period) in the same transaction.
  `{:error, :package_terms_choice_required}` when the change reaches
  holders and no choice was made. Returns the package and, per member
  told, `%{user_id, subscription_id, now_count, next_on}`.
  """
  @callback update(Ecto.UUID.t(), map(), choice(), Ecto.UUID.t() | nil) ::
              {:ok, %{package: map(), notices: [map()], term_change_id: Ecto.UUID.t() | nil}}
              | {:error, term()}

  @doc """
  Applies the subscription's pending update whose day is `on` or earlier.
  Runs inside the caller's transaction; returns whether one was applied.
  """
  @callback apply_due(Ecto.UUID.t(), Date.t()) :: boolean()

  @doc "Applies every pending update due by `today`; returns the memberships changed."
  @callback apply_due_all(Date.t()) :: [Ecto.UUID.t()]

  @doc "Per subscription id, its term updates (pending first, then newest), at most 10."
  @callback for_subscriptions([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => [map()]}
end
