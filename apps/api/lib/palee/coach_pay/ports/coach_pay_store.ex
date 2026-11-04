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
  Totals of the statements of these periods, without their lines:
  `[%{period_id, coach_user_id, total_cents, line_count}]` (ADR-382).
  """
  @callback statement_totals(period_ids :: [id()]) :: [map()]
  @doc """
  Replaces the calculated lines of a draft period (lines added by hand,
  `source_type = manual`, stay), merges each coach's rule terms into the
  statement and updates the statement and period totals.
  """
  @callback replace_lines(
              period_id :: id(),
              %{id() => [map()]},
              terms :: %{id() => map()},
              DateTime.t()
            ) ::
              {:ok, map()} | {:error, term()}
  @doc "Adds a line by hand, merging `terms` (`%{id => terms}`) into the statement's."
  @callback add_line(period_id :: id(), coach_user_id :: id(), map(), terms :: map()) ::
              {:ok, map()} | {:error, term()}
  @doc "ADR-382: changes a line's amount basis and the totals."
  @callback update_line_basis(period_id :: id(), line_id :: id(), String.t()) ::
              :ok | {:error, term()}
  @doc "Removes a line added by hand (`source_type = manual`)."
  @callback delete_adjustment(period_id :: id(), line_id :: id()) :: :ok | {:error, term()}

  # Recurring allowances taken off a person for a period (ADR-510)
  @doc "The period's skips: `[%{id, user_id, pay_item_id, ...}]`."
  @callback item_skips(period_id :: id()) :: [map()]
  @doc """
  Takes a calculated recurring allowance line off its person for the
  period: records the skip, removes that allowance's lines of the person
  and updates the totals.
  """
  @callback skip_pay_item_line(period_id :: id(), line_id :: id(), actor_id :: id() | nil) ::
              :ok | {:error, term()}
  @callback delete_skip(period_id :: id(), skip_id :: id()) :: :ok | {:error, term()}

  # Pay items (ADR-382)
  @callback list_items(filters :: map()) :: [map()]
  @callback get_item(id()) :: map() | nil
  @callback insert_item(map()) :: {:ok, map()} | {:error, term()}
  @callback update_item(id(), map()) :: {:ok, map()} | {:error, term()}

  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
end
