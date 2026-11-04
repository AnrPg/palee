defmodule Palee.Analytics.KpiStore do
  @moduledoc """
  Facade of the ADR-462 KPI store: every read runs in the box's scope
  (`RepoContext.run/2`).
  """

  alias Palee.Infrastructure.Tenancy.{GymClock, RepoContext}

  @default_adapter Palee.Infrastructure.Analytics.EctoKpiStore

  @doc "Runs `fun` in the tenant scope of `context`."
  def run(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @doc "The scoped gym's zone and local date (inside `run/2`)."
  def gym_clock, do: {GymClock.zone() || "Etc/UTC", GymClock.today()}

  def scope(filter, zone, window, home_user_ids),
    do: adapter().scope(filter, zone, window, home_user_ids)

  def compute(key, scope), do: adapter().compute(key, scope)
  def cohort_size(scope), do: adapter().cohort_size(scope)
  def people_ids(scope), do: adapter().people_ids(scope)

  defp adapter, do: Application.get_env(:palee, :kpi_store, @default_adapter)
end
