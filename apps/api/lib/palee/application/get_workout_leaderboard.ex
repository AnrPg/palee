defmodule Palee.Application.GetWorkoutLeaderboard do
  @moduledoc """
  ADR-356 (CP-D2): one WOD's leaderboard with filters and a percentile for
  each score.

  Results are those `WorkoutDayLeaderboard` ranks (in-app executions and
  logged scores, never a result kept `private`), from people who opted in to
  the box's leaderboards. The filters (`LeaderboardFilters`) choose the
  slice: division, age group, scale level, branch, time window and buddies.
  The slice is ranked by the WOD's scored section, then every row gets its
  `percentile` and `top_percent` (`ScorePercentile`).

  Principle §4.4: comparison is shown only to people who opted in. A viewer
  who has not gets their own result (no rank, no percentile) and
  `opted_in: false`, so the screen can offer the opt-in instead.
  """

  alias Palee.{Buddies, Execution, Gamification, Identity, Organizations, Workouts}
  alias Palee.Application.WorkoutDayLeaderboard

  @max_rows 200
  @all_since ~U[2000-01-01 00:00:00Z]

  def call(%{organization_id: organization_id, user_id: viewer_id} = context, workout_id, params)
      when is_binary(organization_id) do
    now = Map.get(params, :now) || DateTime.utc_now()

    with {:ok, filters} <- Gamification.parse_leaderboard_filters(params),
         :ok <- authorize_branch(context, filters),
         %{} = workout <- Workouts.get_workout(context, workout_id) || {:error, :not_found} do
      zone = Organizations.organization_timezone(organization_id)
      date = filters.date || now |> DateTime.shift_zone!(zone) |> DateTime.to_date()
      filters = %{filters | date: date}
      {from, to} = window(filters, zone, now)

      section = WorkoutDayLeaderboard.ranked_section(workout)

      results =
        context
        |> WorkoutDayLeaderboard.results(workout.id, from, to)
        |> Enum.reject(&(&1.journal_visibility == "private"))

      profiles = profiles(context, results)
      viewer_opted_in = Map.has_key?(profiles, viewer_id)

      rows =
        if viewer_opted_in do
          ranked(context, results, profiles, filters, section, viewer_id, now)
        else
          []
        end

      {:ok,
       %{
         workout: %{id: workout.id, title: workout.title},
         section: section && Map.take(section, [:id, :name, :score_type, :unit]),
         opted_in: viewer_opted_in,
         profile: Map.get(profiles, viewer_id),
         filters: Gamification.present_leaderboard_filters(filters),
         options: options(context),
         total: length(rows),
         rows: Enum.take(rows, @max_rows),
         me: me(rows, results, section, viewer_id, viewer_opted_in)
       }}
    end
  end

  def call(_context, _workout_id, _params), do: {:error, :organization_context_required}

  # The slice, ranked, with percentiles and the people's names.
  defp ranked(context, results, profiles, filters, section, viewer_id, now) do
    year = filters.date.year
    homes = homes(context, filters, profiles)
    buddies = buddies(context, filters, viewer_id, now)

    results
    |> Enum.filter(&Map.has_key?(profiles, &1.user_id))
    |> Enum.filter(fn result ->
      profile = Map.fetch!(profiles, result.user_id)

      Gamification.leaderboard_filter_keep?(
        filters,
        %{
          division: profile.division,
          birth_year: profile.birth_year,
          scale_level_slug: result.scale_level_slug,
          home_location_id: Map.get(homes, result.user_id),
          buddy?: result.user_id == viewer_id or MapSet.member?(buddies, result.user_id)
        },
        year
      )
    end)
    |> Execution.rank_workout_results(section)
    |> Enum.reject(&is_nil(&1.rank))
    |> Gamification.annotate_percentiles()
    |> with_people(viewer_id)
  end

  defp with_people(rows, viewer_id) do
    people =
      case Enum.map(rows, & &1.user_id) |> Enum.uniq() do
        [] -> %{}
        ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})
      end

    Enum.map(rows, fn row ->
      person = Map.get(people, row.user_id, %{})

      %{
        rank: row.rank,
        user_id: row.user_id,
        nickname: Map.get(person, :nickname),
        avatar_url: Map.get(person, :avatar_url),
        scale_level_slug: row.scale_level_slug,
        value: score_value(row.score),
        unit: score_unit(row.score),
        percentile: row.percentile,
        top_percent: row.top_percent,
        me: row.user_id == viewer_id
      }
    end)
  end

  # The viewer's own place in the slice, or their best result alone when
  # they are outside it (or did not opt in: no rank, no percentile).
  defp me(rows, results, section, viewer_id, opted_in) do
    case Enum.find(rows, & &1.me) do
      %{} = row when opted_in ->
        row

      _none ->
        results
        |> Enum.filter(&(&1.user_id == viewer_id))
        |> Execution.rank_workout_results(section)
        |> Enum.find(&(not is_nil(&1.rank)))
        |> case do
          nil ->
            nil

          row ->
            %{
              rank: nil,
              user_id: viewer_id,
              scale_level_slug: row.scale_level_slug,
              value: score_value(row.score),
              unit: score_unit(row.score),
              percentile: nil,
              top_percent: nil,
              me: true
            }
        end
    end
  end

  defp profiles(context, results) do
    ids = results |> Enum.map(& &1.user_id) |> Enum.uniq()
    viewer = context.user_id

    Gamification.with_tenant_context(context, fn ->
      Gamification.leaderboard_profiles(Enum.uniq([viewer | ids]))
    end)
  end

  defp homes(context, %{scope: "branch"}, profiles) do
    Map.new(Map.keys(profiles), fn user_id ->
      summary = Organizations.membership_summary(context.organization_id, user_id)
      {user_id, summary && summary.home_location_id}
    end)
  end

  defp homes(_context, _filters, _profiles), do: %{}

  defp buddies(context, %{buddies: true}, viewer_id, now) do
    Buddies.with_context(context, fn ->
      context
      |> Buddies.list_links(viewer_id, now)
      |> Enum.filter(&Buddies.open_link?(&1, now))
      |> MapSet.new(&Buddies.other_party(&1, viewer_id))
    end)
  end

  defp buddies(_context, _filters, _viewer_id, _now), do: MapSet.new()

  # A branch-scoped staff member or member only filters on branches they
  # may see (ADR-186); anyone may pick «box».
  defp authorize_branch(context, %{scope: "branch", location_id: location_id}),
    do: Organizations.authorize_location(context, location_id)

  defp authorize_branch(_context, _filters), do: :ok

  defp window(filters, zone, now) do
    case Gamification.leaderboard_window(filters.window, filters.date) do
      nil -> {@all_since, DateTime.add(now, 86_400, :second)}
      {from, to} -> {local_midnight(from, zone), local_midnight(to, zone)}
    end
  end

  defp options(context) do
    Gamification.leaderboard_filter_options()
    |> Map.put(
      :scales,
        context
        |> Workouts.list_scale_levels()
        |> Enum.map(&%{slug: &1.slug, label: &1.label})
    )
  end

  defp score_value(nil), do: nil
  defp score_value(score), do: (score["value"] || score[:value]) |> then(&(&1 && to_string(&1)))

  defp score_unit(nil), do: nil
  defp score_unit(score), do: score["unit"] || score[:unit]

  # Midnight can be skipped or repeated by a DST change in some zones.
  defp local_midnight(date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, at} -> at
      {:ambiguous, first, _second} -> first
      {:gap, _before, just_after} -> just_after
    end
    |> DateTime.shift_zone!("Etc/UTC")
  end
end
