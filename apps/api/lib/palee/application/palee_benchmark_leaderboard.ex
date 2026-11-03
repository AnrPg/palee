defmodule Palee.Application.PaleeBenchmarkLeaderboard do
  @moduledoc """
  ADR-394: the «Όλο το Palee» board of a WOD a coach tagged as a benchmark.

  Results stay in their boxes' tables under forced RLS. The one cross-box
  read is the `palee_benchmark_results` SECURITY DEFINER function, which
  returns only the results of WODs tagged with the same benchmark, kept in
  a box, not voided and not kept `private`, of people who chose `share`,
  plus the viewer's own. Each row carries an opaque person reference,
  nickname, box name, scale level, division and age group — never another
  person's account id or avatar.

  Each WOD is ranked by its own scored section (the box board's rule),
  read through `palee_benchmark_workout_sections`. Its value is compared
  across boxes only when the section's direction matches the benchmark's
  (a Fran scored as reps does not rank). Each person counts once, with their
  best result; the slice gets percentiles as in ADR-356.

  Only someone who answered the question takes part: `share` ranks for
  everyone, `see_only` ranks only on the viewer's own screen.
  """

  alias Palee.{Execution, Gamification}
  alias Palee.Application.WorkoutDayLeaderboard

  @max_rows 200
  @benchmark_section "benchmark"

  @doc """
  `{:ok, %{rows, total, me}}` for a viewer who answered,
  `{:error, :palee_leaderboard_consent_required}` for one who did not.
  """
  def call(context, benchmark, filters, {from, to}) do
    Gamification.with_tenant_context(context, fn ->
      case Gamification.palee_leaderboard_consent(context.user_id) do
        nil -> {:error, :palee_leaderboard_consent_required}
        _choice -> {:ok, read(context, benchmark, filters, from, to)}
      end
    end)
  end

  defp read(context, benchmark, filters, from, to) do
    results = Gamification.palee_benchmark_results(benchmark.key, from, to, filters.date.year)

    sections =
      benchmark.key
      |> Gamification.palee_benchmark_workout_sections(Enum.map(results, & &1.workout_id))
      |> Map.new(fn {id, workout} -> {id, WorkoutDayLeaderboard.ranked_section(workout)} end)

    rows =
      results
      |> Enum.flat_map(&comparable(&1, Map.get(sections, &1.workout_id), benchmark))
      |> Enum.filter(&Gamification.palee_leaderboard_keep?(filters, &1))
      |> Execution.rank_workout_results(%{
        id: @benchmark_section,
        score_type: if(benchmark.lower_is_better, do: "time", else: "reps")
      })
      |> Enum.reject(&is_nil(&1.rank))
      |> Gamification.annotate_percentiles()
      |> Enum.map(&present(&1, context.user_id))

    %{
      total: length(rows),
      rows: Enum.take(rows, @max_rows),
      me: Enum.find(rows, & &1.me)
    }
  end

  # One result as a number on the benchmark's scale, keeping what it showed.
  defp comparable(_result, nil, _benchmark), do: []

  defp comparable(result, section, benchmark) do
    with true <-
           Execution.score_lower_is_better?(section.score_type) == benchmark.lower_is_better,
         [%{score: %{} = score}] <- Execution.rank_workout_results([result], section),
         value when is_number(value) <- Execution.score_sort_value(score, section.score_type) do
      [
        result
        |> Map.put(:user_id, result.person_ref)
        |> Map.put(:shown, score)
        |> Map.put(:section_scores, [%{"section_key" => @benchmark_section, "value" => value}])
      ]
    else
      _not_comparable -> []
    end
  end

  defp present(row, viewer_id) do
    %{
      rank: row.rank,
      user_id: if(row.viewer?, do: viewer_id),
      nickname: row.nickname,
      avatar_url: nil,
      box_name: row.box_name,
      scale_level_slug: row.scale_level_slug,
      value: value(row.shown),
      unit: row.shown["unit"] || row.shown[:unit],
      percentile: row.percentile,
      top_percent: row.top_percent,
      me: row.viewer?
    }
  end

  defp value(score), do: (score["value"] || score[:value]) |> then(&(&1 && to_string(&1)))
end
