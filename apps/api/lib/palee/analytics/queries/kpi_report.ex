defmodule Palee.Analytics.Queries.KpiReport do
  @moduledoc """
  ADR-462: the staff KPIs of a filter, each for the period and the previous
  one of equal length, each cut at its active baseline (`MetricBaseline`).
  Runs inside the box's tenant session (`Analytics.kpi_report/5`).

  k-anonymity (§3): under an age or gender selection, a figure whose
  people number fewer than the threshold is `suppressed`, and so is every
  breakdown row covering fewer people.
  """

  alias Palee.Analytics.Domain.{AnalyticsFilter, KAnonymity, MetricBaseline, MetricRegistry}
  alias Palee.Analytics.KpiStore
  alias Palee.TimeZones.ZonedTime

  @doc "The UTC `[start, finish)` windows of the filter and its previous period."
  def windows(%AnalyticsFilter{} = filter, zone) do
    previous = AnalyticsFilter.previous(filter)
    %{current: window(filter, zone), previous: window(previous, zone)}
  end

  defp window(%AnalyticsFilter{from: from, to: to}, zone),
    do: {ZonedTime.start_of_day(from, zone), ZonedTime.start_of_day(Date.add(to, 1), zone)}

  def call(%AnalyticsFilter{} = filter, keys, baselines, home_user_ids, zone) do
    windows = windows(filter, zone)
    demographic? = AnalyticsFilter.demographic?(filter)
    cohorts = cohorts(demographic?, filter, zone, windows, home_user_ids)

    Map.new(keys, fn key ->
      {:ok, metric} = MetricRegistry.fetch(:organization, key)
      baseline = if metric.resettable, do: Map.get(baselines, key)
      cut = MetricBaseline.windows(windows, baseline)

      current =
        value(metric, filter, zone, cut.current, home_user_ids, cohorts.current, demographic?)

      previous =
        cut.previous &&
          value(metric, filter, zone, cut.previous, home_user_ids, cohorts.previous, demographic?)

      {key, MetricBaseline.entry(metric, current, previous, cut.since)}
    end)
  end

  @doc "One metric over an explicit window, without baselines (reset history)."
  def over(%AnalyticsFilter{} = filter, key, window, zone) do
    with {:ok, metric} <- MetricRegistry.fetch(:organization, key) do
      scope = KpiStore.scope(filter, zone, window, nil)
      {:ok, KpiStore.compute(metric.key, scope)}
    end
  end

  defp cohorts(false, _filter, _zone, _windows, _home), do: %{current: nil, previous: nil}

  defp cohorts(true, filter, zone, windows, home) do
    %{
      current: KpiStore.cohort_size(KpiStore.scope(filter, zone, windows.current, home)),
      previous: KpiStore.cohort_size(KpiStore.scope(filter, zone, windows.previous, home))
    }
  end

  # The demographic breakdowns ignore the age and gender selection and are
  # k-anonymous per bucket themselves.
  defp value(%{key: "demographics." <> _} = metric, filter, zone, window, home, _cohort, _demo),
    do: KpiStore.compute(metric.key, KpiStore.scope(filter, zone, window, home))

  defp value(metric, filter, zone, window, home, cohort, demographic?) do
    if demographic? and not KAnonymity.shown?(cohort) do
      %{suppressed: true}
    else
      result = KpiStore.compute(metric.key, KpiStore.scope(filter, zone, window, home))
      if demographic?, do: Map.update!(result, :rows, &KAnonymity.suppress_rows/1), else: result
    end
  end
end
