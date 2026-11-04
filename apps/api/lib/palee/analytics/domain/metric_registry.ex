defmodule Palee.Analytics.Domain.MetricRegistry do
  @moduledoc """
  Every analytics metric key Palee computes (ADR-462 §4), in one list: the
  staff KPIs of Στατιστικά (`scope: :organization`) and the member's own
  Πρόοδος sections (`scope: :member`). Keys are stable API: the web maps
  them to labels and the reset endpoints validate against this registry.

  `kind`:

    * `:flow` - counts what happened in the period (resettable: the period
      starts at the later of `from` and the active baseline);
    * `:snapshot` - the state at the period's end (members today, MRR); a
      reset has no meaning for a state, so these are not resettable;
    * `:breakdown` - grouped rows over the period (resettable as a flow).

  `unit` tells the client how to format the value: `count`, `percent`,
  `ratio`, `cents`, `days`, `per_1000` or `rows`.
  """

  @organization [
    # Overview
    {"overview.active_members", :overview, :snapshot, "count"},
    {"overview.net_member_change", :overview, :flow, "count"},
    {"overview.new_members", :overview, :flow, "count"},
    {"overview.churn_rate", :overview, :flow, "percent"},
    {"overview.trial_conversion", :overview, :flow, "percent"},
    {"overview.members_at_risk", :overview, :snapshot, "count"},
    # Training
    {"training.class_fill_rate", :training, :flow, "percent"},
    {"training.no_show_rate", :training, :flow, "percent"},
    {"training.late_cancellations", :training, :flow, "count"},
    {"training.waitlist_conversion", :training, :flow, "percent"},
    {"training.visits_per_member_week", :training, :flow, "ratio"},
    {"training.attendance_by_hour", :training, :breakdown, "rows"},
    {"training.attendance_by_weekday", :training, :breakdown, "rows"},
    {"training.execution_kpis", :training, :flow, "rows"},
    # Coaching
    {"coaching.classes_per_coach", :coaching, :breakdown, "rows"},
    {"coaching.athletes_per_coach", :coaching, :snapshot, "rows"},
    {"coaching.programme_adherence", :coaching, :flow, "percent"},
    {"coaching.review_rating_per_coach", :coaching, :breakdown, "rows"},
    # Engagement
    {"engagement.weekly_active_users", :engagement, :flow, "count"},
    {"engagement.challenge_participation", :engagement, :flow, "percent"},
    {"engagement.booking_streaks", :engagement, :flow, "count"},
    {"engagement.event_mix", :engagement, :breakdown, "rows"},
    # Health
    {"health.injuries_per_1000_attendances", :health, :flow, "per_1000"},
    {"health.mean_recovery_days", :health, :flow, "days"},
    {"health.top_body_areas", :health, :breakdown, "rows"},
    # Finance
    {"finance.mrr", :finance, :snapshot, "cents"},
    {"finance.arpm", :finance, :flow, "cents"},
    {"finance.ltv", :finance, :flow, "cents"},
    {"finance.on_time_collection", :finance, :flow, "percent"},
    {"finance.days_sales_outstanding", :finance, :flow, "days"},
    {"finance.revenue_per_package", :finance, :breakdown, "rows"},
    # Demographics (opt-in, k-anonymous)
    {"demographics.age_bands", :overview, :snapshot, "rows"},
    {"demographics.genders", :overview, :snapshot, "rows"}
  ]

  @member [
    {"progress.totals", :progress, :flow, "rows"},
    {"progress.weekly", :progress, :flow, "rows"},
    {"progress.consistency", :progress, :flow, "rows"},
    {"progress.score_history", :progress, :flow, "rows"},
    {"progress.exercise_loads", :progress, :flow, "rows"},
    {"progress.by_source", :progress, :flow, "rows"},
    {"progress.pr_timeline", :progress, :flow, "rows"},
    {"progress.depth.coverage", :progress, :flow, "rows"},
    {"progress.depth.qualities", :progress, :flow, "rows"},
    {"progress.depth.load", :progress, :flow, "rows"}
  ]

  @scopes [:organization, :member]

  @metrics (for {list, scope} <- [{@organization, :organization}, {@member, :member}],
                {key, section, kind, unit} <- list do
              %{
                key: key,
                scope: scope,
                section: section,
                kind: kind,
                unit: unit,
                resettable: kind != :snapshot
              }
            end)

  @by_key Map.new(@metrics, &{{&1.scope, &1.key}, &1})

  def scopes, do: @scopes

  @doc "Every metric, in display order."
  def all, do: @metrics

  @doc "The metrics of a scope (`:organization` or `:member`)."
  def all(scope) when scope in @scopes, do: Enum.filter(@metrics, &(&1.scope == scope))

  @doc "The metric keys of a scope."
  def keys(scope), do: scope |> all() |> Enum.map(& &1.key)

  @doc "The metric keys of one staff section."
  def section_keys(section),
    do: :organization |> all() |> Enum.filter(&(&1.section == section)) |> Enum.map(& &1.key)

  def fetch(scope, key) when scope in @scopes and is_binary(key) do
    case Map.fetch(@by_key, {scope, key}) do
      {:ok, metric} -> {:ok, metric}
      :error -> {:error, :unknown_metric}
    end
  end

  def fetch(_scope, _key), do: {:error, :unknown_metric}

  @doc "A metric that may be reset, or why not."
  def resettable(scope, key) do
    with {:ok, metric} <- fetch(scope, key) do
      if metric.resettable, do: {:ok, metric}, else: {:error, :metric_not_resettable}
    end
  end
end
