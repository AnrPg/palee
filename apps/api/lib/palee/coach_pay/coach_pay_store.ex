defmodule Palee.CoachPay.CoachPayStore do
  @moduledoc "ADR-341: dispatches to the configured `Palee.CoachPay.Ports.CoachPayStore`."

  @behaviour Palee.CoachPay.Ports.CoachPayStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :coach_pay_store)

  @doc "Runs `fun` inside the tenant scope of `context`."
  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  @impl true
  def list_rules(filters), do: adapter().list_rules(filters)
  @impl true
  def get_rule(id), do: adapter().get_rule(id)
  @impl true
  def insert_rule(attrs), do: adapter().insert_rule(attrs)
  @impl true
  def update_rule(id, attrs), do: adapter().update_rule(id, attrs)
  @impl true
  def rules_between(from, to), do: adapter().rules_between(from, to)
  @impl true
  def list_periods(filters), do: adapter().list_periods(filters)
  @impl true
  def get_period(id), do: adapter().get_period(id)
  @impl true
  def lock_period(id), do: adapter().lock_period(id)
  @impl true
  def insert_period(attrs), do: adapter().insert_period(attrs)
  @impl true
  def update_period(id, attrs), do: adapter().update_period(id, attrs)
  @impl true
  def statements(period_id), do: adapter().statements(period_id)
  @impl true
  def statements_for_coach(coach_user_id, statuses),
    do: adapter().statements_for_coach(coach_user_id, statuses)

  @impl true
  def replace_lines(period_id, lines, now), do: adapter().replace_lines(period_id, lines, now)
  @impl true
  def add_line(period_id, coach_user_id, attrs),
    do: adapter().add_line(period_id, coach_user_id, attrs)

  @impl true
  def delete_adjustment(period_id, line_id), do: adapter().delete_adjustment(period_id, line_id)
  @impl true
  def transaction(fun), do: adapter().transaction(fun)
end
