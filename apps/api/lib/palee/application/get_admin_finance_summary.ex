defmodule Palee.Application.GetAdminFinanceSummary do
  @moduledoc """
  The finance page summary. ADR-186 §7: `location_ids` filters it to some
  branches (inside the person's scope), and `branches` splits the headline
  figures per branch when the person sees two or more.

  ADR-462: the same period and filters as Στατιστικά (`from`/`to` or
  `days`, package, tenure, opt-in age and gender). The paid revenue of the
  window follows the period; `kpis` holds the finance KPIs (`finance.*`)
  for the period and the previous one, each after its reset baseline.
  """

  alias Palee.Application.{BranchReport, GetAdminAnalyticsSummary}
  alias Palee.{Analytics, Finance}

  def call, do: {:ok, Finance.financial_summary()}

  def call(context, params) do
    params = stringify(params)
    {zone, today} = Analytics.gym_clock(context)

    with {:ok, filter} <- Analytics.parse_analytics_filter(params, today) do
      report = BranchReport.resolve(context, params)
      filter = Analytics.analytics_filter_locations(filter, report.filter)

      people =
        if Analytics.analytics_people_filtered?(filter),
          do: Analytics.filter_people(context, filter, report.user_ids),
          else: report.user_ids

      period_params = %{"since" => filter.from, "until" => filter.to, "days" => filter.days}

      scoped =
        params
        |> BranchReport.scope_params(report)
        |> Map.merge(period_params)
        |> then(fn params -> if people, do: Map.put(params, "user_ids", people), else: params end)

      summary = Finance.financial_summary(context, scoped)
      previous = Analytics.previous_analytics_filter(filter)

      previous_totals =
        Finance.financial_summary(
          context,
          Map.merge(scoped, %{"since" => previous.from, "until" => previous.to})
        ).totals

      branches =
        BranchReport.splits(context, report, fn users, location_id ->
          totals =
            Finance.financial_summary(
              context,
              params
              |> Map.merge(period_params)
              |> BranchReport.split_params(users, location_id)
            ).totals

          %{
            active_memberships: totals.active_memberships,
            paid_revenue_cents: totals.paid_revenue_cents,
            revenue_by_stream: totals.revenue_by_stream,
            outstanding_invoice_balance_cents: totals.outstanding_invoice_balance_cents
          }
        end)

      baselines = Analytics.metric_baselines(context, :organization)
      keys = Analytics.section_metric_keys(:finance)

      {:ok,
       summary
       |> Map.put(:previous_totals, %{
         paid_revenue_cents: previous_totals.paid_revenue_cents,
         revenue_by_stream: previous_totals.revenue_by_stream
       })
       |> Map.put(:kpis, Analytics.kpi_report(context, filter, keys, baselines, report.user_ids))
       |> Map.put(:period, GetAdminAnalyticsSummary.period(filter, zone))
       |> Map.put(:filter, Analytics.analytics_filter_params(filter))
       |> Map.put(:branch_filter, BranchReport.filter_payload(report))
       |> Map.put(:branches, branches)}
    end
  end

  defp stringify(params) when is_map(params),
    do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  defp stringify(_params), do: %{}
end
