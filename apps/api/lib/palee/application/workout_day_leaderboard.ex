defmodule Palee.Application.WorkoutDayLeaderboard do
  @moduledoc """
  The ranking of one WOD's results over a window of the gym's day (ADR-138
  D6), shared by the `#wod-σήμερα` card and the box screen (ADR-253).

  Results are the in-app executions and logged scores of the window, read in
  the gym's scope. A result kept `private` in its owner's journal never
  ranks. Only members who opted in to leaderboards (`leaderboard_opt_ins`)
  rank, plus `include_user_id` (the card shows the viewer their own place);
  `exclude_user_ids` are left out before ranking. The ranking follows the
  WOD's scored section.
  """

  alias Palee.{Execution, Gamification, Workouts}

  @default_limit 20

  @doc """
  `%{section, rows}`: the scored section (nil when the WOD has none) and up to
  `limit` rows `%{rank, user_id, scale_level_slug, value, unit, opted_in,
  variant}`. Options: `include_user_id`, `exclude_user_ids`, `limit`,
  `results` and `variant_results` (already read, to avoid reading twice).

  ADR-785 (6A): members who did their own «Παραλλαγή» of this WOD come after
  every ranked row, unranked (`rank: nil`, `variant: true`), each with their
  own score; the same opt-in and privacy rules apply.
  """
  def rank(context, workout, %DateTime{} = from, %DateTime{} = to, opts \\ []) do
    section = ranked_section(workout)
    viewer_id = opts[:include_user_id]
    excluded = MapSet.new(opts[:exclude_user_ids] || [])

    results =
      (opts[:results] || results(context, workout && workout.id, from, to))
      |> Enum.reject(&(&1.journal_visibility == "private"))
      |> Enum.reject(&MapSet.member?(excluded, &1.user_id))

    opted_in = opted_in(context, results)

    rows =
      results
      |> Enum.filter(&(MapSet.member?(opted_in, &1.user_id) or &1.user_id == viewer_id))
      |> Execution.rank_workout_results(section)
      |> Enum.reject(&is_nil(&1.rank))

    ranked_ids = MapSet.new(rows, & &1.user_id)

    variants =
      (opts[:variant_results] || variant_results(context, workout, from, to))
      |> Enum.reject(&(&1.journal_visibility == "private"))
      |> Enum.reject(
        &(MapSet.member?(excluded, &1.user_id) or MapSet.member?(ranked_ids, &1.user_id))
      )

    variant_opted_in = opted_in(context, variants)

    variant_rows =
      Enum.filter(
        variants,
        &(MapSet.member?(variant_opted_in, &1.user_id) or &1.user_id == viewer_id)
      )

    all_opted_in = MapSet.union(opted_in, variant_opted_in)

    rows =
      (Enum.map(rows, &Map.put(&1, :variant, false)) ++
         Enum.map(variant_rows, &Map.merge(&1, %{rank: nil, variant: true})))
      |> Enum.take(opts[:limit] || @default_limit)
      |> Enum.map(fn row ->
        %{
          rank: row.rank,
          user_id: row.user_id,
          scale_level_slug: if(row.variant, do: nil, else: row.scale_level_slug),
          value: row.score && to_string(row.score["value"] || row.score[:value]),
          unit: row.score && (row.score["unit"] || row.score[:unit]),
          opted_in: MapSet.member?(all_opted_in, row.user_id),
          part_of_time: Map.get(row, :part_of_time),
          variant: row.variant
        }
      end)

    %{section: section, rows: rows}
  end

  @doc """
  ADR-785: each member's best result of their own variant of `workout` in
  the window (a class variant that stands in for it), scored by the
  variant's own scored section. Results keep `:score` (nil when unscored).
  """
  def variant_results(_context, nil, _from, _to), do: []

  def variant_results(context, %{id: workout_id}, %DateTime{} = from, %DateTime{} = to) do
    # The window is a gym day; its dates in UTC may start the day before.
    context
    |> Workouts.list_variants_standing_in_for(
      workout_id,
      from |> DateTime.to_date() |> Date.add(-1),
      DateTime.to_date(to)
    )
    |> Enum.flat_map(fn variant ->
      variant_workout = Workouts.get_workout(context, variant.master_workout_id)

      context
      |> results(variant.master_workout_id, from, to)
      |> Enum.filter(&(&1.user_id == variant.user_id))
      |> Execution.rank_workout_results(ranked_section(variant_workout))
      |> Enum.take(1)
    end)
  end

  def variant_results(_context, _workout, _from, _to), do: []

  @doc "Every finished result of the WOD in the window (executions and log entries)."
  def results(_context, nil, _from, _to), do: []

  def results(context, workout_id, from, to),
    do: Execution.list_workout_results(context, workout_id, from, to)

  @doc """
  The WOD's scored section; for a workout written in text sections
  (ADR-180), the first score its coach set.
  """
  def ranked_section(nil), do: nil

  def ranked_section(workout) do
    case Execution.training_log_scoreable_sections(workout) do
      [section | _rest] -> section
      [] -> workout |> Execution.text_section_metrics() |> List.first()
    end
  end

  defp opted_in(context, results) do
    Gamification.with_tenant_context(context, fn ->
      results
      |> Enum.map(& &1.user_id)
      |> Enum.uniq()
      |> Gamification.leaderboard_opted_in_user_ids()
    end)
    |> MapSet.new()
  end
end
