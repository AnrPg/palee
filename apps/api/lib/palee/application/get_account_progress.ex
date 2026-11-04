defmodule Palee.Application.GetAccountProgress do
  @moduledoc """
  `GET /api/me/progress` (ADR-150, ADR-162; board 17, Q4): Πρόοδος across
  every provider, «Όλοι» by default. The same sections the per-provider page
  returns (`ProgressStats`: totals, weekly, consistency, sources, score
  history, PR timeline), built from every completed workout of the account,
  with score history grouped by canonical workout identity so one benchmark
  done at two providers is one line. Points and PRs carry their source;
  `by_source` counts sessions per source; `available_sources` lists every
  source with a completed workout, unfiltered (ADR-285: the «Πηγή» chip).

  Filters (`ProgressFilter`): `range`, `sources`, `exercise`. The weekly
  chart, consistency and its day grid span the range (ADR-194). The
  per-provider page stays gated by its package (ADR-098); this account view
  is the member's own data across providers and is not, like PRs.
  """

  alias Palee.Application.AccountTraining
  alias Palee.{Analytics, Execution, Journal, Pantheon}
  alias Palee.Analytics.Domain.ProgressStats

  def call(context, params, today \\ Date.utc_today()) do
    with {:ok, filter} <- Analytics.parse_progress_filter(params) do
      loaded = AccountTraining.load(context)
      since = Analytics.progress_since(filter, today)

      executions =
        loaded.executions
        |> Enum.filter(&source?(filter.sources, &1.source_label))
        |> Enum.filter(&in_range?(&1, since))
        |> Enum.filter(
          &Execution.exercise_matches?(filter.exercise, Map.get(&1, :exercise_names))
        )

      labels = Map.new(executions, &{&1.id, &1.source_label})

      weeks = Analytics.progress_weeks(filter, today, first_day(executions))

      # ADR-462 §5: a stat the member reset counts only what came after.
      baselines = Analytics.metric_baselines(context, :member)
      build = fn key -> build_stats(after_baseline(executions, baselines[key]), today, weeks) end
      stats = build.(nil)

      {:ok,
       stats
       |> Map.put(:totals, build.("progress.totals").totals)
       |> Map.merge(Map.take(build.("progress.weekly"), [:weekly, :days]))
       |> Map.put(:consistency, build.("progress.consistency").consistency)
       |> Map.put(:exercise_loads, build.("progress.exercise_loads").exercise_loads)
       |> Map.put(
         :score_history,
         label_points(build.("progress.score_history").score_history, labels)
       )
       |> Map.put(
         :by_source,
         by_source(after_baseline(executions, baselines["progress.by_source"]))
       )
       |> Map.put(:available_sources, available_sources(loaded.executions))
       |> Map.put(
         :pr_timeline,
         context
         |> pr_timeline(loaded.directory, filter, since)
         |> Enum.filter(
           &on_or_after?(&1.beaten_on, baseline_date(baselines["progress.pr_timeline"]))
         )
       )
       |> Map.put(
         :metric_baselines,
         Map.new(baselines, fn {key, at} -> {key, DateTime.to_iso8601(at)} end)
       )
       |> Map.put(:filter, Analytics.progress_filter_params(filter))
       |> Map.put(:active_filter_count, Analytics.progress_filter_active_count(filter))}
    end
  end

  defp build_stats(executions, today, weeks) do
    executions
    |> Enum.map(&Map.put(&1, :master_workout_id, &1.workout_key))
    |> ProgressStats.build(today, weeks)
  end

  defp after_baseline(executions, nil), do: executions

  defp after_baseline(executions, %DateTime{} = baseline) do
    Enum.filter(executions, fn execution ->
      at = execution.completed_at_utc || execution.started_at_utc
      at != nil and DateTime.compare(at, baseline) == :gt
    end)
  end

  defp baseline_date(nil), do: nil
  defp baseline_date(%DateTime{} = at), do: DateTime.to_date(at)

  defp first_day(executions) do
    executions
    |> Enum.filter(&(&1.status == "completed" and &1.completed_at_utc))
    |> Enum.map(&DateTime.to_date(&1.completed_at_utc))
    |> Enum.min(Date, fn -> nil end)
  end

  defp label_points(history, labels) do
    Enum.map(history, fn line ->
      Map.update!(line, :points, fn points ->
        Enum.map(points, &Map.put(&1, :source, Map.get(labels, &1.execution_id)))
      end)
    end)
  end

  defp by_source(executions) do
    executions
    |> Enum.filter(&(&1.status == "completed" and &1.completed_at_utc))
    |> Enum.frequencies_by(& &1.source_label)
    |> Enum.map(fn {source, sessions} -> %{source: source, sessions: sessions} end)
    |> Enum.sort_by(&{-&1.sessions, &1.source.name || ""})
  end

  # ADR-285: what the «Πηγή» chip could narrow to, before any filter, so the
  # chip neither hides a source the range happens to leave out nor vanishes
  # while a source is picked.
  defp available_sources(executions) do
    executions
    |> Enum.filter(&(&1.status == "completed" and &1.completed_at_utc))
    |> Enum.map(&AccountTraining.token(&1.source_label))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # PRs are the member's own across providers (ADR-129); each keeps the
  # provider it was set at.
  defp pr_timeline(%{user_id: user_id} = context, directory, filter, since) do
    Pantheon.with_user_context(context, fn ->
      records = Pantheon.list_records(user_id)
      origin = Map.new(records, &{&1.id, &1.organization_id})

      records
      |> then(&ProgressStats.pr_timeline(Pantheon.list_user_record_history(user_id), &1))
      |> Enum.map(fn entry ->
        Map.put(
          entry,
          :source,
          Journal.entry_source(Map.get(origin, entry.pr_record_id), nil, directory)
        )
      end)
      |> Enum.filter(&source?(filter.sources, &1.source))
      |> Enum.filter(&Execution.exercise_matches?(filter.exercise, [&1.name]))
      |> Enum.filter(&on_or_after?(&1.beaten_on, since))
    end)
  end

  defp source?([], _label), do: true
  defp source?(sources, label), do: AccountTraining.token(label) in sources

  defp in_range?(_execution, nil), do: true

  defp in_range?(execution, since) do
    at = execution.completed_at_utc || execution.started_at_utc
    at != nil and Date.compare(DateTime.to_date(at), since) != :lt
  end

  defp on_or_after?(_on, nil), do: true
  defp on_or_after?(nil, _since), do: false

  defp on_or_after?(on, since) do
    on = if is_binary(on), do: Date.from_iso8601!(on), else: on
    Date.compare(on, since) != :lt
  end
end
