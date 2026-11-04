defmodule Palee.Infrastructure.Analytics.EctoKpiStore do
  @moduledoc """
  The staff KPIs of ADR-462 §3, each by its registry key, computed over one
  `FilterQuery` scope (filter, gym zone, UTC window, people). Every figure
  takes its facts from `FilterQuery`, so all of them honour the same
  filters. Returns `%{value: number | nil, rows: [map]}`; a figure with no
  facts to divide by has `value: nil` (not zero).

  Runs inside the caller's tenant session. Facts are read from the tables
  that are readable in the box's scope; figures whose facts are not (PR
  records, notifications) are not computed here (see ADR-462 §3).
  """

  @behaviour Palee.Analytics.Ports.KpiStore

  import Ecto.Query

  alias Palee.Analytics.Domain.{AnalyticsFilter, EventCatalog, KAnonymity}
  alias Palee.Infrastructure.Analytics.FilterQuery
  alias Palee.Repo

  @months_per_period %{"monthly" => 1, "quarterly" => 3, "semiannual" => 6, "annual" => 12}

  @impl true
  def scope(filter, zone, window, home_user_ids),
    do: FilterQuery.scope(filter, zone, window, home_user_ids)

  @impl true
  def cohort_size(scope) do
    case FilterQuery.people(scope) do
      nil ->
        nil

      people ->
        people
        |> FilterQuery.for_people(%{scope | filter: %AnalyticsFilter{}}, :membership, :user_id)
        |> subquery()
        |> select(count())
        |> Repo.one()
    end
  end

  @impl true
  def people_ids(scope) do
    case FilterQuery.people(scope) do
      nil ->
        nil

      people ->
        people
        |> FilterQuery.for_people(%{scope | filter: %AnalyticsFilter{}}, :membership, :user_id)
        |> Repo.all()
        |> Enum.map(&FilterQuery.load/1)
    end
  end

  @impl true
  def compute(key, scope), do: metric(key, scope)

  ## Overview

  defp metric("overview.active_members", scope),
    do: %{value: count_members(scope, scope.to), rows: []}

  defp metric("overview.net_member_change", scope) do
    before = Date.add(scope.from, -1)
    %{value: count_members(scope, scope.to) - count_members(scope, before), rows: []}
  end

  defp metric("overview.new_members", scope) do
    first_starts =
      from(membership in "memberships",
        where:
          membership.organization_id == ^scope.org and membership.status != "trial" and
            membership.user_type_snapshot in ["member", "athlete"] and
            not is_nil(membership.user_id),
        group_by: membership.user_id,
        select: %{
          user_id: membership.user_id,
          started_on:
            fragment("min(COALESCE(?, ?::date))", membership.starts_on, membership.inserted_at)
        }
      )

    value =
      from(first in subquery(first_starts),
        as: :first,
        where: first.started_on >= ^scope.from and first.started_on <= ^scope.to,
        select: count()
      )
      |> FilterQuery.for_people(scope, :first, :user_id)
      |> Repo.one()

    %{value: value, rows: []}
  end

  defp metric("overview.churn_rate", scope) do
    before = Date.add(scope.from, -1)
    start_set = FilterQuery.members_on(scope, before)
    end_set = FilterQuery.members_on(scope, scope.to)

    {base, churned} =
      from(member in subquery(start_set),
        left_join: kept in subquery(end_set),
        on: kept.user_id == member.user_id,
        select: {count(), count() |> filter(is_nil(kept.user_id))}
      )
      |> Repo.one()

    %{value: percent(churned, base), rows: [%{key: "churned", count: churned, base: base}]}
  end

  defp metric("overview.trial_conversion", scope) do
    query =
      from(trial in "scheduling_trial_requests",
        as: :trial,
        left_join: class in "scheduled_classes",
        as: :class,
        on: class.id == trial.scheduled_class_id,
        left_join: type in "class_types",
        as: :type,
        on: type.id == class.class_type_id,
        where:
          trial.organization_id == ^scope.org and trial.inserted_at >= ^scope.start and
            trial.inserted_at < ^scope.finish
      )
      |> live_class_filter(scope)

    {total, converted} =
      query
      |> select([trial: trial], {count(), count() |> filter(not is_nil(trial.converted_at))})
      |> Repo.one()

    %{
      value: percent(converted, total),
      rows: [%{key: "converted", count: converted, base: total}]
    }
  end

  defp metric("overview.members_at_risk", scope) do
    rows =
      from(risk in "retention_risks",
        as: :risk,
        where:
          risk.organization_id == ^scope.org and risk.level in ["medium", "high"] and
            (is_nil(risk.snoozed_until) or risk.snoozed_until < ^scope.to),
        group_by: risk.level,
        select: {risk.level, count()}
      )
      |> FilterQuery.for_people(scope, :risk, :user_id)
      |> Repo.all()

    %{
      value: rows |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
      rows: Enum.map(rows, fn {level, count} -> %{key: level, count: count} end)
    }
  end

  ## Training

  defp metric("training.class_fill_rate", scope) do
    booked =
      from(booking in "bookings",
        as: :booking_rows,
        where: booking.organization_id == ^scope.org and booking.status == "approved",
        group_by: booking.scheduled_class_id,
        select: %{scheduled_class_id: booking.scheduled_class_id, booked: count()}
      )
      |> FilterQuery.for_people(scope, :booking_rows, :user_id)

    {capacity, filled} =
      scope
      |> FilterQuery.classes()
      |> join(:left, [class: class], booked in subquery(booked),
        as: :booked,
        on: booked.scheduled_class_id == class.id
      )
      |> where([class: class], not is_nil(class.capacity) and class.capacity > 0)
      |> select([class: class, booked: booked], {
        sum(class.capacity),
        sum(fragment("LEAST(COALESCE(?, 0), ?)", booked.booked, class.capacity))
      })
      |> Repo.one()

    capacity = to_int(capacity)
    filled = to_int(filled)
    %{value: percent(filled, capacity), rows: [%{key: "booked", count: filled, base: capacity}]}
  end

  defp metric("training.no_show_rate", scope) do
    counts = attendance_counts(scope)
    missed = Map.get(counts, "no_show", 0) + Map.get(counts, "missed", 0)
    base = missed + Map.get(counts, "attended", 0)
    %{value: percent(missed, base), rows: [%{key: "no_show", count: missed, base: base}]}
  end

  defp metric("training.late_cancellations", scope),
    do: %{value: Map.get(attendance_counts(scope), "late_cancel", 0), rows: []}

  defp metric("training.waitlist_conversion", scope) do
    {total, booked} =
      scope
      |> FilterQuery.bookings()
      |> where([booking: booking], not is_nil(booking.waitlisted_at))
      |> select([booking: booking], {
        count(),
        count() |> filter(booking.status == "approved")
      })
      |> Repo.one()

    %{value: percent(booked, total), rows: [%{key: "booked", count: booked, base: total}]}
  end

  defp metric("training.visits_per_member_week", scope) do
    {visits, people} =
      scope
      |> FilterQuery.attendance()
      |> where([record: record], record.status == "attended")
      |> select([record: record], {count(), count(record.user_id, :distinct)})
      |> Repo.one()

    weeks = max(Date.diff(scope.to, scope.from) + 1, 1) / 7

    value = if people > 0, do: Float.round(visits / people / weeks, 2), else: nil
    %{value: value, rows: [%{key: "visits", count: visits, people: people}]}
  end

  defp metric("training.attendance_by_hour", scope),
    do: attendance_by(scope, "hour")

  defp metric("training.attendance_by_weekday", scope),
    do: attendance_by(scope, "isodow")

  ## Coaching

  defp metric("coaching.classes_per_coach", scope) do
    classes =
      scope
      |> FilterQuery.classes()
      |> where([class: class], not is_nil(class.coach_user_id))
      |> group_by([class: class], class.coach_user_id)
      |> select([class: class], {class.coach_user_id, count()})
      |> Repo.all()
      |> Map.new()

    attended =
      scope
      |> FilterQuery.attendance()
      |> where([record: record], record.status == "attended")
      |> group_by(
        [record: record, class: class],
        fragment("COALESCE(?, ?)", record.coach_user_id, class.coach_user_id)
      )
      |> select(
        [record: record, class: class],
        {fragment("COALESCE(?, ?)", record.coach_user_id, class.coach_user_id), count(),
         count(record.user_id, :distinct)}
      )
      |> Repo.all()
      |> Map.new(fn {coach, count, people} -> {coach, {count, people}} end)

    rows =
      (Map.keys(classes) ++ Map.keys(attended))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(fn coach ->
        {attendances, people} = Map.get(attended, coach, {0, 0})

        %{
          key: FilterQuery.load(coach),
          classes: Map.get(classes, coach, 0),
          attendances: attendances,
          people: people
        }
      end)
      |> Enum.sort_by(&{-&1.classes, &1.key})

    %{value: length(rows), rows: rows}
  end

  defp metric("coaching.athletes_per_coach", scope) do
    rows =
      from(relationship in "coaching_relationships",
        as: :relationship,
        where:
          relationship.organization_id == ^scope.org and relationship.started_at < ^scope.finish and
            (is_nil(relationship.ended_at) or relationship.ended_at >= ^scope.finish),
        group_by: relationship.coach_user_id,
        select: {relationship.coach_user_id, count(relationship.client_user_id, :distinct)}
      )
      |> coach_filter(scope, :relationship)
      |> FilterQuery.for_people(scope, :relationship, :client_user_id)
      |> Repo.all()
      |> Enum.map(fn {coach, athletes} ->
        %{key: FilterQuery.load(coach), athletes: athletes, people: athletes}
      end)
      |> Enum.sort_by(&{-&1.athletes, &1.key})

    value =
      case rows do
        [] -> nil
        rows -> Float.round(Enum.sum(Enum.map(rows, & &1.athletes)) / length(rows), 1)
      end

    %{value: value, rows: rows}
  end

  defp metric("coaching.programme_adherence", scope) do
    done =
      from(execution in "workout_executions",
        where:
          execution.user_id == parent_as(:assignment).athlete_id and
            execution.master_workout_id == parent_as(:workout).master_workout_id and
            not is_nil(execution.completed_at_utc) and
            fragment(
              "?::date BETWEEN COALESCE(?, ?) - 1 AND COALESCE(?, ?) + 7",
              execution.completed_at_utc,
              parent_as(:assignment).scheduled_for,
              parent_as(:workout).scheduled_for,
              parent_as(:assignment).scheduled_for,
              parent_as(:workout).scheduled_for
            ),
        select: 1
      )

    {assigned, completed} =
      from(assignment in "assigned_workout_athletes",
        as: :assignment,
        join: workout in "assigned_workouts",
        as: :workout,
        on: workout.id == assignment.assigned_workout_id,
        where:
          assignment.organization_id == ^scope.org and
            (is_nil(assignment.athlete_status) or assignment.athlete_status != "rejected") and
            fragment("COALESCE(?, ?)", assignment.scheduled_for, workout.scheduled_for) >=
              ^scope.from and
            fragment("COALESCE(?, ?)", assignment.scheduled_for, workout.scheduled_for) <=
              ^scope.to and
            fragment("COALESCE(?, ?)", assignment.scheduled_for, workout.scheduled_for) <=
              fragment("CURRENT_DATE"),
        select: {count(), count() |> filter(exists(done))}
      )
      |> FilterQuery.for_people(scope, :assignment, :athlete_id)
      |> Repo.one()

    %{
      value: percent(completed, assigned),
      rows: [%{key: "completed", count: completed, base: assigned}]
    }
  end

  defp metric("coaching.review_rating_per_coach", scope) do
    rows =
      from(review in "reviews",
        as: :review,
        join: class in "scheduled_classes",
        as: :class,
        on: class.id == review.target_id,
        left_join: type in "class_types",
        as: :type,
        on: type.id == class.class_type_id,
        where:
          review.organization_id == ^scope.org and review.target_type == "class_slot" and
            not is_nil(review.rating) and not is_nil(class.coach_user_id) and
            review.inserted_at >= ^scope.start and review.inserted_at < ^scope.finish,
        group_by: class.coach_user_id,
        select:
          {class.coach_user_id, avg(review.rating), count(), count(review.user_id, :distinct)}
      )
      |> live_class_filter(scope)
      |> FilterQuery.for_people(scope, :review, :user_id)
      |> Repo.all()
      |> Enum.map(fn {coach, rating, count, people} ->
        %{
          key: FilterQuery.load(coach),
          rating: round_decimal(rating),
          count: count,
          people: people
        }
      end)
      |> Enum.sort_by(&{-&1.count, &1.key})

    total = rows |> Enum.map(& &1.count) |> Enum.sum()

    value =
      if total > 0,
        do: Float.round(Enum.sum(Enum.map(rows, &(&1.rating * &1.count))) / total, 2),
        else: nil

    %{value: value, rows: rows}
  end

  ## Engagement

  defp metric("engagement.weekly_active_users", scope) do
    events =
      scope
      |> FilterQuery.events()
      |> where(
        [event: event],
        not is_nil(event.user_id) and
          (is_nil(event.actor_role_snapshot) or
             event.actor_role_snapshot not in ^FilterQuery.staff_roles())
      )
      |> select([event: event], %{
        user_id: event.user_id,
        week:
          fragment(
            "date_trunc('week', (? AT TIME ZONE 'UTC') AT TIME ZONE ?)::date",
            event.occurred_at,
            ^scope.zone
          )
      })

    attended =
      scope
      |> FilterQuery.attendance()
      |> where([record: record], record.status == "attended")
      |> select([record: record, class: class], %{
        user_id: record.user_id,
        week:
          fragment(
            "date_trunc('week', (COALESCE(?, ?) AT TIME ZONE 'UTC') AT TIME ZONE ?)::date",
            record.class_starts_at,
            class.scheduled_at,
            ^scope.zone
          )
      })

    pairs = events |> union(^attended)

    rows =
      from(pair in subquery(pairs),
        group_by: pair.week,
        order_by: pair.week,
        select: {pair.week, count(pair.user_id, :distinct)}
      )
      |> Repo.all()

    weeks = max(div(Date.diff(scope.to, scope.from) + 1 + 6, 7), 1)
    total = rows |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    %{
      value: Float.round(total / weeks, 1),
      rows: Enum.map(rows, fn {week, people} -> %{key: Date.to_iso8601(week), people: people} end)
    }
  end

  defp metric("engagement.challenge_participation", scope) do
    challenges =
      from(challenge in "seasonal_challenges",
        where:
          challenge.organization_id == ^scope.org and challenge.starts_at <= ^scope.to and
            challenge.ends_at >= ^scope.from,
        select: challenge.id
      )

    case Repo.aggregate(challenges, :count) do
      0 ->
        %{value: nil, rows: []}

      count ->
        participants =
          from(progress in "user_challenge_progress",
            as: :progress,
            where:
              progress.organization_id == ^scope.org and
                progress.challenge_id in subquery(challenges) and progress.progress > 0 and
                progress.inserted_at < ^scope.finish,
            select: count(progress.user_id, :distinct)
          )
          |> FilterQuery.for_people(scope, :progress, :user_id)
          |> Repo.one()

        members = count_members(scope, scope.to)

        %{
          value: percent(participants, members),
          rows: [%{key: "participants", count: participants, base: members, challenges: count}]
        }
    end
  end

  defp metric("engagement.booking_streaks", scope) do
    weeks =
      scope
      |> FilterQuery.bookings()
      |> where([booking: booking], booking.status == "approved" and not is_nil(booking.user_id))
      |> select([booking: booking, class: class], {
        booking.user_id,
        fragment(
          "date_trunc('week', (? AT TIME ZONE 'UTC') AT TIME ZONE ?)::date",
          class.scheduled_at,
          ^scope.zone
        )
      })
      |> distinct(true)
      |> Repo.all()

    last_week = Date.beginning_of_week(scope.to)

    streaks =
      weeks
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {_user, weeks} -> streak(MapSet.new(weeks), last_week, 0) end)
      |> Enum.reject(&(&1 == 0))

    buckets =
      Enum.frequencies_by(streaks, fn
        1 -> "1"
        weeks when weeks <= 3 -> "2_3"
        weeks when weeks <= 7 -> "4_7"
        _weeks -> "8_plus"
      end)

    %{
      value: Enum.count(streaks, &(&1 >= 4)),
      rows:
        Enum.map(~w(1 2_3 4_7 8_plus), fn key ->
          count = Map.get(buckets, key, 0)
          %{key: key, people: count, count: count}
        end)
    }
  end

  defp metric("engagement.event_mix", scope) do
    rows =
      scope
      |> FilterQuery.events()
      |> group_by([event: event], event.event_name)
      |> select([event: event], {event.event_name, count(), count(event.user_id, :distinct)})
      |> Repo.all()

    people = Map.new(rows, fn {name, _count, people} -> {name, people} end)
    counts = Map.new(rows, fn {name, count, _people} -> {name, count} end)

    groups =
      counts
      |> EventCatalog.group_by_category()
      |> Enum.map(fn group ->
        Map.merge(group, %{
          key: group.category,
          count: group.total,
          events: Enum.map(group.events, &Map.put(&1, :people, Map.get(people, &1.name, 0)))
        })
      end)

    %{value: counts |> Map.values() |> Enum.sum(), rows: groups}
  end

  ## Health

  defp metric("health.injuries_per_1000_attendances", scope) do
    injuries =
      injuries(scope)
      |> where(
        [injury: injury],
        injury.started_on >= ^scope.from and injury.started_on <= ^scope.to
      )
      |> select(count())
      |> Repo.one()

    attended = Map.get(attendance_counts(scope), "attended", 0)
    value = if attended > 0, do: Float.round(injuries * 1000 / attended, 1), else: nil
    %{value: value, rows: [%{key: "injuries", count: injuries, base: attended}]}
  end

  defp metric("health.mean_recovery_days", scope) do
    {healed, days} =
      injuries(scope)
      |> where(
        [injury: injury],
        not is_nil(injury.healed_on) and not is_nil(injury.started_on) and
          injury.healed_on >= ^scope.from and injury.healed_on <= ^scope.to
      )
      |> select([injury: injury], {
        count(),
        avg(fragment("(? - ?)", injury.healed_on, injury.started_on))
      })
      |> Repo.one()

    %{value: round_decimal(days), rows: [%{key: "healed", count: healed}]}
  end

  defp metric("health.top_body_areas", scope) do
    rows =
      injuries(scope)
      |> where(
        [injury: injury],
        injury.started_on >= ^scope.from and injury.started_on <= ^scope.to and
          not is_nil(injury.body_area)
      )
      |> group_by([injury: injury], injury.body_area)
      |> select([injury: injury], {injury.body_area, count(), count(injury.user_id, :distinct)})
      |> Repo.all()
      |> Enum.map(fn {area, count, people} -> %{key: area, count: count, people: people} end)
      |> Enum.sort_by(&{-&1.count, &1.key})
      |> Enum.take(5)

    %{value: rows |> Enum.map(& &1.count) |> Enum.sum(), rows: rows}
  end

  ## Finance

  defp metric("finance.mrr", scope) do
    rows =
      from(subscription in "membership_package_subscriptions",
        join: membership in "memberships",
        as: :member,
        on: membership.id == subscription.membership_id,
        where:
          subscription.organization_id == ^scope.org and
            subscription.status in ["active", "expiring"] and
            subscription.billing_period_snapshot in ^Map.keys(@months_per_period) and
            subscription.starts_on <= ^scope.to and
            (is_nil(subscription.ends_on) or subscription.ends_on >= ^scope.to),
        group_by: subscription.billing_period_snapshot,
        select: {subscription.billing_period_snapshot, sum(subscription.price_cents_snapshot)}
      )
      |> package_filter(scope)
      |> FilterQuery.for_people(scope, :member, :user_id)
      |> Repo.all()

    value =
      rows
      |> Enum.map(fn {period, cents} ->
        to_int(cents) / Map.fetch!(@months_per_period, period)
      end)
      |> Enum.sum()
      |> round()

    %{value: value, rows: []}
  end

  defp metric("finance.arpm", scope) do
    revenue = paid_revenue(scope)
    members = count_members(scope, scope.to)

    %{
      value: arpm(revenue, members, scope),
      rows: [%{key: "revenue", cents: revenue, base: members}]
    }
  end

  defp metric("finance.ltv", scope) do
    revenue = paid_revenue(scope)
    members = count_members(scope, scope.to)
    churn = metric("overview.churn_rate", scope).value

    value =
      with arpm when is_number(arpm) <- arpm(revenue, members, scope),
           churn when is_number(churn) and churn > 0 <- churn do
        monthly_churn = churn / 100 / months(scope)
        round(arpm / monthly_churn)
      else
        _not_computable -> nil
      end

    %{value: value, rows: [%{key: "estimate", churn_percent: churn}]}
  end

  defp metric("finance.on_time_collection", scope) do
    on_time =
      from(payment in "membership_payments",
        where:
          payment.finance_invoice_id == parent_as(:invoice).id and
            payment.payment_status == "paid" and
            is_nil(payment.deleted_at) and payment.paid_on <= parent_as(:invoice).due_date,
        select: fragment("COALESCE(sum(?), 0)", payment.amount_cents)
      )

    {due, paid_on_time} =
      invoices(scope)
      |> where(
        [invoice: invoice],
        not is_nil(invoice.due_date) and invoice.due_date >= ^scope.from and
          invoice.due_date <= ^scope.to and invoice.due_date < fragment("CURRENT_DATE")
      )
      |> select([invoice: invoice], {
        count(),
        count() |> filter(subquery(on_time) >= invoice.total_cents)
      })
      |> Repo.one()

    %{
      value: percent(paid_on_time, due),
      rows: [%{key: "on_time", count: paid_on_time, base: due}]
    }
  end

  defp metric("finance.days_sales_outstanding", scope) do
    last_paid =
      from(payment in "membership_payments",
        where:
          payment.organization_id == ^scope.org and payment.payment_status == "paid" and
            is_nil(payment.deleted_at) and not is_nil(payment.finance_invoice_id),
        group_by: payment.finance_invoice_id,
        select: %{
          invoice_id: payment.finance_invoice_id,
          paid_on: max(payment.paid_on),
          paid_cents: sum(payment.amount_cents)
        }
      )

    {count, days} =
      invoices(scope)
      |> join(:inner, [invoice: invoice], paid in subquery(last_paid),
        as: :paid,
        on: paid.invoice_id == invoice.id
      )
      |> where(
        [invoice: invoice, paid: paid],
        not is_nil(invoice.issue_date) and paid.paid_cents >= invoice.total_cents and
          paid.paid_on >= ^scope.from and paid.paid_on <= ^scope.to
      )
      |> select([invoice: invoice, paid: paid], {
        count(),
        avg(fragment("GREATEST(? - ?, 0)", paid.paid_on, invoice.issue_date))
      })
      |> Repo.one()

    %{value: round_decimal(days), rows: [%{key: "paid_invoices", count: count}]}
  end

  defp metric("finance.revenue_per_package", scope) do
    rows =
      scope
      |> payments()
      |> join(:left, [payment: payment], subscription in "membership_package_subscriptions",
        as: :subscription,
        on: subscription.id == payment.membership_package_subscription_id
      )
      |> group_by([subscription: s], [s.package_code_snapshot, s.package_family_snapshot])
      |> select([payment: payment, subscription: s, reversal: reversal], {
        s.package_code_snapshot,
        s.package_family_snapshot,
        sum(fragment("GREATEST(? - COALESCE(?, 0), 0)", payment.amount_cents, reversal.reversed)),
        count(payment.membership_id, :distinct)
      })
      |> Repo.all()
      |> Enum.map(fn {code, family, cents, people} ->
        %{key: code || "none", family: family, cents: to_int(cents), people: people}
      end)
      |> Enum.sort_by(&{-&1.cents, &1.key})

    %{value: rows |> Enum.map(& &1.cents) |> Enum.sum(), rows: rows}
  end

  defp metric("demographics.age_bands", scope), do: demographics(scope, :age)
  defp metric("demographics.genders", scope), do: demographics(scope, :gender)

  defp metric(_key, _scope), do: %{value: nil, rows: []}

  ## Helpers

  defp count_members(scope, on) do
    scope
    |> FilterQuery.members_on(on)
    |> subquery()
    |> select(count())
    |> Repo.one()
  end

  defp attendance_counts(scope) do
    scope
    |> FilterQuery.attendance()
    |> group_by([record: record], record.status)
    |> select([record: record], {record.status, count()})
    |> Repo.all()
    |> Map.new()
  end

  defp attendance_by(scope, part) do
    rows =
      scope
      |> FilterQuery.attendance()
      |> where([record: record], record.status == "attended")
      |> local_part(part, scope.zone)
      |> group_by([part: part], part.key)
      |> select(
        [record: record, part: part],
        {part.key, count(), count(record.user_id, :distinct)}
      )
      |> Repo.all()
      |> Enum.map(fn {key, count, people} -> %{key: key, count: count, people: people} end)
      |> Enum.sort_by(& &1.key)

    %{value: rows |> Enum.map(& &1.count) |> Enum.sum(), rows: rows}
  end

  # The gym-local hour (0-23) or ISO weekday (1 = Monday) a class started,
  # as a lateral `:part` binding.
  defp local_part(query, "hour", zone) do
    join(
      query,
      :inner_lateral,
      [record: record, class: class],
      part in fragment(
        "SELECT extract(hour from ((COALESCE(?, ?) AT TIME ZONE 'UTC') AT TIME ZONE ?))::int AS key",
        record.class_starts_at,
        class.scheduled_at,
        ^zone
      ),
      as: :part,
      on: true
    )
  end

  defp local_part(query, "isodow", zone) do
    join(
      query,
      :inner_lateral,
      [record: record, class: class],
      part in fragment(
        "SELECT extract(isodow from ((COALESCE(?, ?) AT TIME ZONE 'UTC') AT TIME ZONE ?))::int AS key",
        record.class_starts_at,
        class.scheduled_at,
        ^zone
      ),
      as: :part,
      on: true
    )
  end

  defp live_class_filter(query, %{filter: filter} = scope) do
    if AnalyticsFilter.classes_filtered?(filter) do
      # The class dimensions alone, whenever the class is.
      unbounded = %{scope | start: ~U[1900-01-01 00:00:00Z], finish: ~U[2999-01-01 00:00:00Z]}
      classes = unbounded |> FilterQuery.classes() |> select([class: class], class.id)
      where(query, [class: class], class.id in subquery(classes))
    else
      query
    end
  end

  defp coach_filter(query, %{filter: %{coach_ids: []}}, _binding), do: query

  defp coach_filter(query, %{filter: %{coach_ids: ids}}, binding) do
    ids = FilterQuery.dump_ids(ids)
    where(query, [{^binding, row}], row.coach_user_id in ^ids)
  end

  defp injuries(scope) do
    from(injury in "injury_reports",
      as: :injury,
      where: injury.organization_id == ^scope.org
    )
    |> FilterQuery.for_people(scope, :injury, :user_id)
  end

  defp invoices(scope) do
    from(invoice in "finance_invoices",
      as: :invoice,
      where:
        invoice.organization_id == ^scope.org and is_nil(invoice.deleted_at) and
          is_nil(invoice.voided_at) and invoice.status not in ["draft", "void", "voided"] and
          invoice.total_cents > 0
    )
    |> FilterQuery.for_people(scope, :invoice, :user_id)
  end

  defp payments(scope) do
    reversals =
      from(reversal in "finance_payment_reversals",
        where: is_nil(reversal.deleted_at),
        group_by: reversal.membership_payment_id,
        select: %{
          membership_payment_id: reversal.membership_payment_id,
          reversed: sum(reversal.amount_cents)
        }
      )

    from(payment in "membership_payments",
      as: :payment,
      join: membership in "memberships",
      as: :member,
      on: membership.id == payment.membership_id,
      left_join: reversal in subquery(reversals),
      as: :reversal,
      on: reversal.membership_payment_id == payment.id,
      where:
        payment.organization_id == ^scope.org and payment.payment_status == "paid" and
          is_nil(payment.deleted_at) and payment.paid_on >= ^scope.from and
          payment.paid_on <= ^scope.to
    )
    |> FilterQuery.for_people(scope, :member, :user_id)
  end

  defp paid_revenue(scope) do
    scope
    |> payments()
    |> select(
      [payment: payment, reversal: reversal],
      sum(fragment("GREATEST(? - COALESCE(?, 0), 0)", payment.amount_cents, reversal.reversed))
    )
    |> Repo.one()
    |> to_int()
  end

  defp package_filter(query, %{filter: %{package_families: [], package_ids: []}}), do: query

  defp package_filter(query, %{filter: filter}) do
    families = filter.package_families
    ids = FilterQuery.dump_ids(filter.package_ids)

    where(
      query,
      [s],
      s.package_family_snapshot in ^families or s.membership_package_id in ^ids
    )
  end

  defp demographics(scope, kind) do
    members =
      FilterQuery.members_on(%{scope | filter: without_demographics(scope.filter)}, scope.to)

    rows =
      from(member in subquery(members),
        left_join: opt_in in "leaderboard_opt_ins",
        on: opt_in.user_id == member.user_id and opt_in.organization_id == ^scope.org,
        select: {opt_in.division, opt_in.birth_year}
      )
      |> Repo.all()

    {keys, counts} =
      case kind do
        :gender ->
          {AnalyticsFilter.genders(),
           Enum.frequencies_by(rows, fn {division, _year} -> division || "unknown" end)}

        :age ->
          {AnalyticsFilter.age_bands(),
           Enum.frequencies_by(rows, fn {_division, year} ->
             AnalyticsFilter.age_band(year, scope.to)
           end)}
      end

    %{value: length(rows), rows: KAnonymity.buckets(keys, counts)}
  end

  defp without_demographics(filter), do: %{filter | age_bands: [], genders: []}

  defp streak(weeks, week, count) do
    if MapSet.member?(weeks, week),
      do: streak(weeks, Date.add(week, -7), count + 1),
      else: count
  end

  defp months(scope), do: max(Date.diff(scope.to, scope.from) + 1, 1) / 30.44

  defp arpm(_revenue, 0, _scope), do: nil
  defp arpm(revenue, members, scope), do: round(revenue / months(scope) / members)

  defp percent(_part, 0), do: nil
  defp percent(_part, nil), do: nil
  defp percent(part, base), do: Float.round(part * 100 / base, 1)

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = value), do: value |> Decimal.round() |> Decimal.to_integer()
  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_float(value), do: round(value)

  defp round_decimal(nil), do: nil
  defp round_decimal(%Decimal{} = value), do: value |> Decimal.to_float() |> Float.round(2)
  defp round_decimal(value) when is_number(value), do: Float.round(value / 1, 2)
end
