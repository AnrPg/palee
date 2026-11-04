defmodule Palee.Application.Programmes.BuyerDays do
  @moduledoc """
  ADR-540 use cases for a buyer: the days of a programme they bought with
  where each one stands («Η μέρα μου»), and the «Έμεινε πίσω» card's two
  answers: «Κάν' τη σήμερα» (`do_today/3`) and «Παράλειψη» (`skip/3`).

  Only the buyer reaches their purchase (tenant RLS on the seller's rows,
  then the purchase's `user_id`). A day is done when every WOD the purchase
  assigned for it was finished: an in-app run of that assigned workout or
  a training-log entry of it (ADR-118).

  Moving a day moves the buyer's own date on its assigned workouts (the
  per-athlete date, like «Μετακίνηση», so another buyer sharing the
  assignment keeps theirs) and its `programme_deliveries` rows, in the same
  transaction as the purchase's new dates. A moved day that was never
  assigned (a purchase paid after its start) is assigned on its new date.
  """

  require Logger

  alias Palee.Application.BroadcastUserSync
  alias Palee.{Execution, Organizations, Programmes, Workouts}

  @doc "The buyer's days, progress and the behind day the card names."
  def show(context, purchase_id) do
    with {:ok, purchase, version} <- load(context, purchase_id) do
      {:ok, present(context, purchase, version)}
    end
  end

  @doc "«Κάν' τη σήμερα»: the behind `day` moves to today, the rest after it."
  def do_today(context, purchase_id, day) do
    today = today(context)

    with {:ok, purchase, version} <- load(context, purchase_id),
         :ok <- delivering(purchase),
         {:ok, _purchase} <-
           Programmes.transaction(context, fn ->
             move(context, purchase.id, version, day, today)
           end) do
      broadcast(context, purchase)

      :telemetry.execute([:palee, :programmes, :day_moved], %{count: 1}, %{
        organization_id: context.organization_id,
        id: purchase.id
      })

      show(context, purchase.id)
    end
  end

  @doc "«Παράλειψη»: the behind `day` is let go; nothing moves."
  def skip(context, purchase_id, day) do
    today = today(context)

    with {:ok, purchase, version} <- load(context, purchase_id),
         :ok <- delivering(purchase),
         {:ok, _purchase} <-
           Programmes.update_schedule(context, purchase.id, fn locked ->
             days = days(context, locked, version, today)

             with {:ok, skipped} <- Programmes.skip_day(days, locked, day),
                  do: {:ok, %{skipped_days: skipped}}
           end) do
      :telemetry.execute([:palee, :programmes, :day_skipped], %{count: 1}, %{
        organization_id: context.organization_id,
        id: purchase.id
      })

      show(context, purchase.id)
    end
  end

  # ── Moving ──────────────────────────────────────────────────────────────

  defp move(context, purchase_id, version, day, today) do
    Programmes.update_schedule(context, purchase_id, fn locked ->
      days = days(context, locked, version, today)

      with {:ok, plan} <- Programmes.do_today(days, locked, day, today),
           :ok <- move_workouts(context, locked, version, plan.moves) do
        {:ok,
         %{
           day_dates: plan.day_dates,
           ends_on: plan.ends_on,
           planned_ends_on: locked.planned_ends_on || locked.ends_on
         }}
      end
    end)
  end

  defp move_workouts(context, purchase, version, moves) do
    deliveries = context |> Programmes.deliveries(purchase.id) |> Enum.group_by(& &1.day)
    wods = Enum.group_by(version.days, & &1["day"], & &1["workout_id"])

    Enum.reduce_while(moves, :ok, fn move, :ok ->
      rows = Map.get(deliveries, move.day, [])

      with :ok <- move_links(context, purchase, rows, move.to),
           :ok <-
             Programmes.move_deliveries(context, purchase.id, Enum.map(rows, &{&1.id, move.to})),
           :ok <- assign_missing(context, purchase, move, Map.get(wods, move.day, []), rows) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp move_links(context, purchase, rows, date) do
    rows
    |> Enum.map(& &1.assigned_workout_id)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn assignment_id, :ok ->
      case Workouts.update_assignment_date(context, assignment_id, purchase.user_id, date) do
        {:ok, _assignment} ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.warning(
            "programme purchase #{purchase.id}: assignment #{assignment_id} not moved: " <>
              inspect(reason)
          )

          {:halt, {:error, :programme_workout_unavailable}}
      end
    end)
  end

  # A day the purchase never assigned (paid after its date): its WODs are
  # assigned on the new date, as delivery does.
  defp assign_missing(_context, _purchase, _move, _wods, [_ | _]), do: :ok
  defp assign_missing(_context, _purchase, _move, [], []), do: :ok

  defp assign_missing(context, purchase, move, wods, []) do
    wods
    |> Enum.reduce_while({:ok, []}, fn workout_id, {:ok, rows} ->
      case Workouts.assign_workout(context, %{
             master_workout_id: workout_id,
             scheduled_for: move.to,
             athlete_ids: [purchase.user_id]
           }) do
        {:ok, assignment} ->
          {:cont,
           {:ok,
            [%{assigned_workout_id: assignment.id, day: move.day, scheduled_for: move.to} | rows]}}

        {:error, _reason} ->
          {:halt, {:error, :programme_workout_unavailable}}
      end
    end)
    |> case do
      {:ok, rows} -> Programmes.record_deliveries(context, purchase.id, purchase.user_id, rows)
      error -> error
    end
  end

  # ── Reading ─────────────────────────────────────────────────────────────

  defp load(context, purchase_id) do
    with %{} = purchase <- Programmes.get_purchase(context, purchase_id) || {:error, :not_found},
         true <- purchase.user_id == context.user_id || {:error, :not_found},
         true <- Programmes.owned?(purchase) || {:error, :not_found},
         %{} = version <-
           Programmes.get_version(context, purchase.version_id) || {:error, :not_found} do
      {:ok, purchase, version}
    end
  end

  defp delivering(purchase) do
    if Programmes.delivering?(purchase),
      do: :ok,
      else: {:error, :programme_purchase_not_active}
  end

  defp present(context, purchase, version) do
    today = today(context)
    days = days(context, purchase, version, today)
    behind = Programmes.next_behind(days)
    active? = Programmes.delivering?(purchase)

    %{
      purchase_id: purchase.id,
      today: today,
      starts_on: purchase.starts_on,
      ends_on: purchase.ends_on,
      planned_ends_on: purchase.planned_ends_on || purchase.ends_on,
      latest_end: Programmes.latest_end(purchase, version.weeks),
      weeks: version.weeks,
      progress: Programmes.purchase_progress(days),
      behind:
        behind &&
          %{
            day: behind.day,
            week: behind.week,
            weekday: behind.weekday,
            date: behind.date,
            can_do_today: active? and Programmes.can_do_today?(days, purchase, behind.day, today),
            can_skip: active?
          },
      days: Enum.map(days, &present_day/1)
    }
  end

  defp present_day(row) do
    %{
      day: row.day,
      week: row.week,
      weekday: row.weekday,
      date: row.date,
      status: row.status,
      workouts:
        Enum.map(row.workouts, fn workout ->
          %{
            workout_id: workout["workout_id"],
            title: workout["title"],
            summary: workout["summary"],
            assigned_workout_id: workout["assigned_workout_id"],
            done: workout["done"] == true
          }
        end)
    }
  end

  # The days with their status; each WOD row carries the buyer's assigned
  # workout and whether it was finished.
  defp days(context, purchase, version, today) do
    deliveries = Programmes.deliveries(context, purchase.id)
    %{finished: finished, workout_of: workout_of} = assignments(context, purchase, deliveries)
    by_day = Enum.group_by(deliveries, & &1.day, & &1.assigned_workout_id)

    rows =
      version.days
      |> Enum.group_by(& &1["day"])
      |> Enum.flat_map(fn {day, wods} ->
        annotate(wods, Map.get(by_day, day, []), workout_of, finished)
      end)

    done =
      rows
      |> Enum.group_by(& &1["day"])
      |> Enum.filter(fn {_day, wods} -> Enum.all?(wods, &(&1["done"] == true)) end)
      |> Enum.map(fn {day, _wods} -> day end)

    Programmes.purchase_days(%{version | days: rows}, purchase, done, today)
  end

  # Pairs each WOD of a day with the assignment of the same day that
  # carries it (the frozen copy), else the next one left.
  defp annotate(wods, assignment_ids, workout_of, finished) do
    {rows, _left} =
      Enum.map_reduce(wods, assignment_ids, fn wod, left ->
        id =
          Enum.find(left, &(Map.get(workout_of, &1) == wod["workout_id"])) || List.first(left)

        done = id != nil and MapSet.member?(finished, id)
        {Map.merge(wod, %{"assigned_workout_id" => id, "done" => done}), List.delete(left, id)}
      end)

    rows
  end

  # The buyer's assignments of this purchase: which were finished (an
  # in-app run or a training-log entry) and the WOD each one carries.
  defp assignments(_context, _purchase, []), do: %{finished: MapSet.new(), workout_of: %{}}

  defp assignments(context, purchase, deliveries) do
    dates = Enum.map(deliveries, & &1.scheduled_for)
    ids = deliveries |> Enum.map(& &1.assigned_workout_id) |> MapSet.new()

    listed =
      context
      |> Workouts.list_assigned_workouts_for_athlete(
        purchase.user_id,
        Enum.min(dates, Date),
        Enum.max(dates, Date)
      )
      |> Enum.filter(&MapSet.member?(ids, &1.id))

    run = for row <- listed, row[:execution_status] == "completed", do: row.id

    logged =
      case Execution.with_training_log_context(context, fn ->
             Execution.list_logged_training_source_ids(purchase.user_id, "assigned_workout")
           end) do
        list when is_list(list) -> list
        _error -> []
      end

    %{
      finished: (run ++ logged) |> MapSet.new() |> MapSet.intersection(ids),
      workout_of: Map.new(listed, &{&1.id, &1.master_workout_id})
    }
  end

  defp broadcast(context, purchase) do
    BroadcastUserSync.for_users([purchase.user_id], ["assigned_workouts"],
      reason: "programme_day_moved",
      payload: %{organization_id: context.organization_id, purchase_id: purchase.id}
    )
  end

  defp today(context), do: Organizations.local_today(context.organization_id, DateTime.utc_now())
end
