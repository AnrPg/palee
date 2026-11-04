defmodule Palee.Application.GetAdminAnalyticsSummary do
  @moduledoc """
  `GET /admin/analytics/summary`: Στατιστικά (overview, training, coaching,
  engagement, health).

  ADR-462: the period is `from`/`to` (gym-local dates; `days` still works)
  and the filters of `AnalyticsFilter`. `kpis` holds every staff KPI by its
  registry key, for the period and the previous one of equal length, each
  counting only data after its active reset baseline (`since`). `period`
  and `filter` echo what was applied. The older blocks (`analytics`,
  `finance`, …) keep their shape, now over the same period and people.
  """

  alias Palee.Application.BranchReport
  alias Palee.{Analytics, Coaching, Execution, Feedback, Finance, Wellbeing}

  @sections ~w(overview training coaching engagement health)a

  # TD-092: every summary reads tenant facts, so the whole dashboard is built
  # in the gym's scope. Unscoped, each read was empty under the production
  # runtime role and the dashboard showed zeros.
  #
  # ADR-186 §7: `location_ids` narrows every figure to some branches: located
  # facts by their branch, the rest by the people whose home branch it is.
  def call(context, params) do
    params = Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)
    {zone, today} = Analytics.gym_clock(context)

    with {:ok, filter} <- Analytics.parse_analytics_filter(params, today) do
      report = BranchReport.resolve(context, params)
      filter = Analytics.analytics_filter_locations(filter, report.filter)
      windows = Analytics.kpi_windows(filter, zone)
      people = people(context, filter, report)

      scoped =
        params
        |> BranchReport.scope_params(report)
        |> Map.merge(period_params(filter, windows))
        |> put_people(people)

      with {:ok, payload} <-
             Analytics.with_tenant_context(context, fn ->
               build(context, scoped, report, windows, people)
             end) do
        baselines = Analytics.metric_baselines(context, :organization)
        keys = Enum.flat_map(@sections, &Analytics.section_metric_keys/1)

        {:ok,
         payload
         |> Map.put(
           :kpis,
           Analytics.kpi_report(context, filter, keys, baselines, report.user_ids)
         )
         |> Map.put(:period, period(filter, zone))
         |> Map.put(:filter, Analytics.analytics_filter_params(filter))
         |> Map.update!(
           :execution,
           &Map.put(&1, :since_baseline, iso(baselines["training.execution_kpis"]))
         )
         |> Map.put(:branch_filter, BranchReport.filter_payload(report))
         |> Map.put(:branches, branches(context, report, scoped, windows))}
      end
    end
  end

  @doc false
  def period(filter, zone) do
    params = Analytics.analytics_filter_params(filter)

    %{
      from: params.from,
      to: params.to,
      days: params.days,
      previous_from: params.previous_from,
      previous_to: params.previous_to,
      time_zone: zone
    }
  end

  # The people the person filters (package, tenure, age, gender) keep, as
  # user ids for the older per-person summaries; nil when none applies.
  defp people(context, filter, report) do
    if Analytics.analytics_people_filtered?(filter) do
      Analytics.filter_people(context, filter, report.user_ids)
    else
      report.user_ids
    end
  end

  defp put_people(params, nil), do: params
  defp put_people(params, users), do: Map.put(params, "user_ids", users)

  defp period_params(filter, %{current: {since, until}}) do
    %{
      "since" => since,
      "until" => until,
      "days" => filter.days,
      "finance_since" => filter.from,
      "finance_until" => filter.to
    }
  end

  defp build(context, params, report, windows, people) do
    analytics = Analytics.analytics_summary(params)
    finance = Finance.financial_summary(finance_params(params))
    coaching = Coaching.get_aggregates(context, people || report.user_ids)
    feedback = Feedback.review_summary(params)
    wellbeing = Wellbeing.injury_summary(params)
    {since, until} = windows.current
    {previous_since, previous_until} = windows.previous

    execution =
      since
      |> Execution.execution_kpis(people, until)
      |> Map.put(:previous, Execution.execution_kpis(previous_since, people, previous_until))

    {:ok,
     %{
       dashboard: dashboard_view(analytics, finance, coaching, feedback, wellbeing),
       analytics: analytics,
       finance: finance,
       coaching: coaching,
       feedback: feedback,
       wellbeing: wellbeing,
       execution: execution
     }}
  end

  defp finance_params(params) do
    params
    |> Map.put("since", params["finance_since"])
    |> Map.put("until", params["finance_until"])
  end

  # Headline figures per branch: its people, their payments and reviews, and
  # the check-ins and attended classes at the branch in the window.
  defp branches(context, report, params, %{current: {since, _until}}) do
    activity = BranchReport.activity_by_branch(context, since)

    BranchReport.splits(context, report, fn users, location_id ->
      finance =
        Finance.financial_summary(
          context,
          params |> finance_params() |> BranchReport.split_params(users, location_id)
        ).totals

      visits = Map.get(activity, location_id, %{check_ins: 0, attended: 0})

      %{
        check_ins: visits.check_ins,
        attended: visits.attended,
        active_memberships: finance.active_memberships,
        paid_revenue_cents: finance.paid_revenue_cents,
        revenue_by_stream: finance.revenue_by_stream
      }
    end)
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)

  defp dashboard_view(analytics, finance, coaching, feedback, wellbeing) do
    %{
      finance: %{
        active_memberships: get_in(finance, [:totals, :active_memberships]) || 0,
        expiring_memberships: get_in(finance, [:totals, :expiring_memberships]) || 0,
        paid_revenue_cents: get_in(finance, [:totals, :paid_revenue_cents]) || 0,
        revenue_by_stream: get_in(finance, [:totals, :revenue_by_stream]) || %{},
        credit_balance_cents: get_in(finance, [:totals, :credit_balance_cents]) || 0,
        aggregate_status: finance[:aggregate_status] || "unknown"
      },
      coaching: coaching,
      cross_context: %{
        event_count: get_in(analytics, [:events, :total]) || 0,
        review_count: feedback[:total] || 0,
        low_rating_count: feedback[:low_rating_count] || 0,
        injury_count: wellbeing[:total] || 0,
        active_injury_count: wellbeing[:active_count] || 0
      }
    }
  end
end
