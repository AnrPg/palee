defmodule Palee.Infrastructure.Analytics.FilterQuery do
  @moduledoc """
  ADR-462 §1: the one place an `AnalyticsFilter` becomes SQL. Every staff
  KPI builds its facts from these queries, so a dimension means the same
  thing in every figure:

    * `classes/2`, `attendance/2`, `bookings/2`, `events/2` - the facts of
      a window narrowed by the class dimensions (branch, class type, level,
      coach, gym-local time of day). Attendance and events read their
      snapshot columns first (ADR-462 §2) and fall back to the live class
      for rows written before the snapshots existed.
    * `people/2` - the people the person dimensions keep (package family or
      package, tenure, opt-in age band and gender), or nil when none
      applies. A branch filter's home-branch people (`home_user_ids`,
      ADR-186 §7) narrow it further.

  Runs inside the caller's tenant session (`RepoContext.run/2`); every
  query names the organization too.
  """

  import Ecto.Query

  alias Palee.Analytics.Domain.AnalyticsFilter
  alias Palee.Infrastructure.Tenancy.RepoContext

  @staff_roles ~w(owner admin coach front_desk accountant janitor)

  def staff_roles, do: @staff_roles

  @doc "The scope of one KPI read: filter, zone, UTC window and people."
  def scope(%AnalyticsFilter{} = filter, zone, {start, finish}, home_user_ids) do
    %{
      filter: filter,
      zone: zone,
      start: start,
      finish: finish,
      from: local_date(start, zone),
      to: finish |> DateTime.add(-1, :second) |> local_date(zone),
      org: org(),
      home_user_ids: dump_ids(home_user_ids)
    }
  end

  def org do
    case RepoContext.current_setting("app.organization_id") do
      id when is_binary(id) -> Ecto.UUID.dump!(id)
      _missing -> raise ArgumentError, "analytics KPIs need a tenant scope"
    end
  end

  def local_date(%DateTime{} = at, zone),
    do: at |> DateTime.shift_zone!(zone) |> DateTime.to_date()

  def dump_ids(nil), do: nil
  def dump_ids(ids) when is_list(ids), do: Enum.map(ids, &Ecto.UUID.dump!/1)

  def load(nil), do: nil
  def load(<<_::128>> = raw), do: Ecto.UUID.load!(raw)
  def load(value), do: value

  ## Classes

  @doc "Scheduled (not cancelled) classes starting in the window, as `:class` (type `:type`)."
  def classes(scope, opts \\ []) do
    from(class in "scheduled_classes",
      as: :class,
      left_join: type in "class_types",
      as: :type,
      on: type.id == class.class_type_id,
      where:
        class.organization_id == ^scope.org and is_nil(class.cancelled_at) and
          class.scheduled_at >= ^scope.start and class.scheduled_at < ^scope.finish
    )
    |> then(fn query ->
      if Keyword.get(opts, :past_only, false),
        do: where(query, [class: class], class.scheduled_at < fragment("now()")),
        else: query
    end)
    |> class_dimensions(scope.filter, scope.zone, :live)
  end

  @doc "Attendance of classes in the window, as `:record` joined to `:class`/`:type`."
  def attendance(scope) do
    from(record in "class_attendance_records",
      as: :record,
      join: class in "scheduled_classes",
      as: :class,
      on: class.id == record.scheduled_class_id,
      left_join: type in "class_types",
      as: :type,
      on: type.id == class.class_type_id,
      where: record.organization_id == ^scope.org,
      where:
        fragment("COALESCE(?, ?)", record.class_starts_at, class.scheduled_at) >= ^scope.start and
          fragment("COALESCE(?, ?)", record.class_starts_at, class.scheduled_at) <
            ^scope.finish
    )
    |> class_dimensions(scope.filter, scope.zone, :snapshot)
    |> for_people(scope, :record, :user_id)
  end

  @doc "Bookings of classes in the window, as `:booking` joined to `:class`/`:type`."
  def bookings(scope) do
    scope
    |> classes()
    |> join(:inner, [class: class], booking in "bookings",
      as: :booking,
      on: booking.scheduled_class_id == class.id and booking.organization_id == ^scope.org
    )
    |> for_people(scope, :booking, :user_id)
  end

  @doc "Analytics events in the window, as `:event`, by their snapshot dimensions."
  def events(scope) do
    from(event in "analytics_events",
      as: :event,
      where:
        event.organization_id == ^scope.org and event.occurred_at >= ^scope.start and
          event.occurred_at < ^scope.finish
    )
    |> event_dimensions(scope.filter, scope.zone)
    |> for_people(scope, :event, :user_id)
  end

  defp class_dimensions(query, filter, zone, source) do
    query
    |> dimension(filter.location_ids, source, :location_id)
    |> dimension(filter.class_type_ids, source, :class_type_id)
    |> dimension(filter.coach_ids, source, :coach_user_id)
    |> levels(filter.levels, source)
    |> time_of_day(filter.time_of_day, zone, source)
  end

  defp dimension(query, [], _source, _column), do: query

  defp dimension(query, ids, :live, column) do
    ids = dump_ids(ids)
    where(query, [class: class], field(class, ^column) in ^ids)
  end

  defp dimension(query, ids, :snapshot, column) do
    ids = dump_ids(ids)

    where(
      query,
      [record: record, class: class],
      fragment("COALESCE(?, ?)", field(record, ^column), field(class, ^column)) in ^ids
    )
  end

  defp levels(query, [], _source), do: query

  defp levels(query, levels, :live),
    do: where(query, [type: type], type.level in ^levels)

  defp levels(query, levels, :snapshot),
    do:
      where(
        query,
        [record: record, type: type],
        fragment("COALESCE(?, ?)", record.level, type.level) in ^levels
      )

  defp time_of_day(query, [], _zone, _source), do: query

  defp time_of_day(query, buckets, zone, source) do
    condition =
      buckets
      |> Enum.map(&AnalyticsFilter.time_of_day_hours/1)
      |> Enum.map(fn {from, to} -> hour_between(source, zone, from, to) end)
      |> Enum.reduce(fn condition, acc -> dynamic(^acc or ^condition) end)

    where(query, ^condition)
  end

  defp hour_between(:live, zone, from, to) do
    dynamic(
      [class: class],
      fragment(
        "extract(hour from ((? AT TIME ZONE 'UTC') AT TIME ZONE ?)) >= ?",
        class.scheduled_at,
        ^zone,
        ^from
      ) and
        fragment(
          "extract(hour from ((? AT TIME ZONE 'UTC') AT TIME ZONE ?)) < ?",
          class.scheduled_at,
          ^zone,
          ^to
        )
    )
  end

  defp hour_between(:snapshot, zone, from, to) do
    dynamic(
      [record: record, class: class],
      fragment(
        "extract(hour from ((COALESCE(?, ?) AT TIME ZONE 'UTC') AT TIME ZONE ?)) >= ?",
        record.class_starts_at,
        class.scheduled_at,
        ^zone,
        ^from
      ) and
        fragment(
          "extract(hour from ((COALESCE(?, ?) AT TIME ZONE 'UTC') AT TIME ZONE ?)) < ?",
          record.class_starts_at,
          class.scheduled_at,
          ^zone,
          ^to
        )
    )
  end

  defp hour_between(:event, zone, from, to) do
    dynamic(
      [event: event],
      fragment(
        "extract(hour from ((? AT TIME ZONE 'UTC') AT TIME ZONE ?)) >= ?",
        event.occurred_at,
        ^zone,
        ^from
      ) and
        fragment(
          "extract(hour from ((? AT TIME ZONE 'UTC') AT TIME ZONE ?)) < ?",
          event.occurred_at,
          ^zone,
          ^to
        )
    )
  end

  defp event_dimensions(query, filter, zone) do
    query
    |> event_dimension(filter.location_ids, :location_id)
    |> event_dimension(filter.class_type_ids, :class_type_id)
    |> event_dimension(filter.coach_ids, :coach_user_id)
    |> then(fn query ->
      if filter.levels == [],
        do: query,
        else: where(query, [event: event], event.level in ^filter.levels)
    end)
    |> then(fn query ->
      if filter.time_of_day == [] do
        query
      else
        condition =
          filter.time_of_day
          |> Enum.map(&AnalyticsFilter.time_of_day_hours/1)
          |> Enum.map(fn {from, to} -> hour_between(:event, zone, from, to) end)
          |> Enum.reduce(fn condition, acc -> dynamic(^acc or ^condition) end)

        where(query, ^condition)
      end
    end)
  end

  defp event_dimension(query, [], _column), do: query

  defp event_dimension(query, ids, column) do
    ids = dump_ids(ids)
    where(query, [event: event], field(event, ^column) in ^ids)
  end

  ## People

  @doc """
  Restricts `binding.column` (a person's user id) to the people the scope
  keeps: the person dimensions and the branch filter's home-branch people.
  """
  def for_people(query, scope, binding, column) do
    query
    |> then(fn query ->
      case scope.home_user_ids do
        nil -> query
        ids -> where(query, [{^binding, row}], field(row, ^column) in ^ids)
      end
    end)
    |> then(fn query ->
      case people(scope) do
        nil -> query
        people -> where(query, [{^binding, row}], field(row, ^column) in subquery(people))
      end
    end)
  end

  @doc """
  The user ids the person dimensions keep, or nil when none applies.
  People are the box's clients with a membership (`memberships`); tenure
  counts from the box membership's `joined_at`, or the first membership's
  start where that is not readable (ADR-462 §1).
  """
  def people(%{filter: filter} = scope) do
    if AnalyticsFilter.people_filtered?(filter), do: people_query(scope), else: nil
  end

  @doc "Every person with a membership, before any person dimension."
  def all_people(scope) do
    from(membership in "memberships",
      as: :membership,
      where: membership.organization_id == ^scope.org and not is_nil(membership.user_id),
      distinct: true,
      select: membership.user_id
    )
  end

  defp people_query(scope) do
    filter = scope.filter

    from(membership in "memberships",
      as: :membership,
      left_join: org_member in "organization_memberships",
      as: :org_member,
      on:
        org_member.user_id == membership.user_id and
          org_member.organization_id == membership.organization_id,
      left_join: opt_in in "leaderboard_opt_ins",
      as: :opt_in,
      on: opt_in.user_id == membership.user_id and opt_in.organization_id == ^scope.org,
      where: membership.organization_id == ^scope.org and not is_nil(membership.user_id),
      group_by: membership.user_id,
      select: membership.user_id
    )
    |> packages(filter, scope)
    |> genders(filter.genders)
    |> ages(filter.age_bands, scope.to)
    |> tenure(filter.tenure_bands, scope.to)
  end

  defp packages(query, %{package_families: [], package_ids: []}, _scope), do: query

  defp packages(query, filter, scope) do
    condition =
      case {filter.package_families, dump_ids(filter.package_ids)} do
        {families, []} ->
          dynamic([subscription: s], s.package_family_snapshot in ^families)

        {[], ids} ->
          dynamic([subscription: s], s.membership_package_id in ^ids)

        {families, ids} ->
          dynamic(
            [subscription: s],
            s.package_family_snapshot in ^families or s.membership_package_id in ^ids
          )
      end

    held =
      from(subscription in "membership_package_subscriptions",
        as: :subscription,
        where:
          subscription.membership_id == parent_as(:membership).id and
            subscription.starts_on <= ^scope.to and
            (is_nil(subscription.ends_on) or subscription.ends_on >= ^scope.from),
        where: ^condition,
        select: 1
      )

    where(query, exists(held))
  end

  defp genders(query, []), do: query

  defp genders(query, genders) do
    known = Enum.reject(genders, &(&1 == "unknown"))

    condition =
      if "unknown" in genders,
        do: dynamic([opt_in: o], is_nil(o.division) or o.division in ^known),
        else: dynamic([opt_in: o], o.division in ^known)

    where(query, ^condition)
  end

  defp ages(query, [], _on), do: query

  defp ages(query, bands, on) do
    condition =
      bands
      |> Enum.map(fn band ->
        case AnalyticsFilter.birth_years(band, on) do
          nil -> dynamic([opt_in: o], is_nil(o.birth_year))
          {min, max} -> dynamic([opt_in: o], o.birth_year >= ^min and o.birth_year <= ^max)
        end
      end)
      |> Enum.reduce(fn condition, acc -> dynamic(^acc or ^condition) end)

    where(query, ^condition)
  end

  defp tenure(query, [], _on), do: query

  defp tenure(query, bands, on) do
    condition =
      bands
      |> Enum.map(fn band ->
        case AnalyticsFilter.joined_between(band, on) do
          {nil, upto} -> joined_on_or_before(upto)
          {after_date, nil} -> joined_after(after_date)
          {after_date, upto} -> dynamic(^joined_after(after_date) and ^joined_on_or_before(upto))
        end
      end)
      |> Enum.reduce(fn condition, acc -> dynamic(^acc or ^condition) end)

    having(query, ^condition)
  end

  # Joined on the box membership's `joined_at`, else the first membership.
  defp joined_after(date) do
    dynamic(
      [membership: m, org_member: om],
      fragment(
        "COALESCE(min(?)::date, min(?), min(?)::date) > ?",
        om.joined_at,
        m.starts_on,
        m.inserted_at,
        ^date
      )
    )
  end

  defp joined_on_or_before(date) do
    dynamic(
      [membership: m, org_member: om],
      fragment(
        "COALESCE(min(?)::date, min(?), min(?)::date) <= ?",
        om.joined_at,
        m.starts_on,
        m.inserted_at,
        ^date
      )
    )
  end

  ## Members over time

  @doc """
  The people holding an active (not trial) membership on `on`, as a query
  of user ids narrowed by the scope's people. A membership is active from
  `starts_on` to `expires_on`, until it was left (`left_at`) or, for a
  cancelled one with no end recorded, its last update.
  """
  def members_on(scope, %Date{} = on) do
    from(membership in "memberships",
      as: :member,
      where:
        membership.organization_id == ^scope.org and not is_nil(membership.user_id) and
          membership.status != "trial" and
          membership.user_type_snapshot in ["member", "athlete"] and
          fragment("COALESCE(?, ?::date)", membership.starts_on, membership.inserted_at) <= ^on and
          (is_nil(membership.expires_on) or membership.expires_on >= ^on) and
          fragment(
            "COALESCE(?::date, CASE WHEN ? = 'cancelled' THEN ?::date END, 'infinity'::date) > ?",
            membership.left_at,
            membership.status,
            membership.updated_at,
            ^on
          ),
      distinct: true,
      select: membership.user_id
    )
    |> for_people(scope, :member, :user_id)
  end
end
