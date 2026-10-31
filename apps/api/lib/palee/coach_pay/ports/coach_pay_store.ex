defmodule Palee.CoachPay.Ports.CoachPayStore do
  @moduledoc """
  Persistence of coach pay rules, periods and statements (ADR-341). Runs
  inside the tenant scope set by `Palee.CoachPay.CoachPayStore`.
  """

  @type id :: Ecto.UUID.t()

  # Rules
  @callback list_rules(filters :: map()) :: [map()]
  @callback get_rule(id()) :: map() | nil
  @callback insert_rule(map()) :: {:ok, map()} | {:error, term()}
  @callback update_rule(id(), map()) :: {:ok, map()} | {:error, term()}
  @doc "Rules that pay for any day between the two dates (inclusive)."
  @callback rules_between(Date.t(), Date.t()) :: [map()]

  # Periods
  @callback list_periods(filters :: map()) :: [map()]
  @callback get_period(id()) :: map() | nil
  @doc "Locks the period row (`FOR UPDATE`) inside the caller's transaction."
  @callback lock_period(id()) :: map() | nil
  @callback insert_period(map()) :: {:ok, map()} | {:error, term()}
  @callback update_period(id(), map()) :: {:ok, map()} | {:error, term()}

  # Statements
  @doc "The period's statements with their lines, ordered."
  @callback statements(period_id :: id()) :: [map()]
  @callback statements_for_coach(coach_user_id :: id(), statuses :: [String.t()]) :: [map()]
  @doc """
  Replaces the calculated lines of a draft period (adjustments stay) and
  updates the statement and period totals, in one transaction.
  """
  @callback replace_lines(period_id :: id(), %{id() => [map()]}, DateTime.t()) ::
              {:ok, map()} | {:error, term()}
  @callback add_line(period_id :: id(), coach_user_id :: id(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback delete_adjustment(period_id :: id(), line_id :: id()) :: :ok | {:error, term()}

  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
end
