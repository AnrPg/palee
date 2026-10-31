defmodule Palee.Infrastructure.Retention.EctoSignalReader do
  @moduledoc """
  ADR-347: risk signals for every active client of a box in a few grouped
  queries over Organizations (who is a client), Scheduling (attendance and
  bookings) and Finance (subscription packages, invoices). Reads only, in
  the box's scope.
  """

  @behaviour Palee.Retention.Ports.SignalReader

  import Ecto.Query

  alias Palee.Repo

  @client_roles ~w(member athlete)

  @impl true
  def signals(%{organization_id: org_id}, %Date{} = today, %DateTime{} = now) do
    {:ok, org} = Ecto.UUID.dump(org_id)

    clients = clients(org)

    if clients == %{} do
      %{}
    else
      ids = Map.keys(clients)
      visits = visits(org, ids, now)
      upcoming = upcoming(org, ids, now)
      cancellations = cancellations(org, ids, now)
      packages = packages(org, ids, today)
      overdue = overdue(org, ids)

      Map.new(clients, fn {id, joined_at} ->
        {recent, baseline, last_at} = Map.get(visits, id, {0, 0, nil})
        package = Map.get(packages, id)

        {Ecto.UUID.load!(id),
         %{
           visits_recent: recent,
           visits_baseline: baseline,
           days_since_last_visit: last_at && Date.diff(today, to_date(last_at)),
           upcoming_bookings: Map.get(upcoming, id, 0),
           cancellations_recent: Map.get(cancellations, id, 0),
           package_ends_in_days: package && Date.diff(package.ends_on, today),
           package_renews: if(package, do: package.renews, else: true),
           overdue_invoices: Map.get(overdue, id, 0),
           member_for_days: joined_at && Date.diff(today, to_date(joined_at))
         }}
      end)
    end
  end

  defp clients(org) do
    from(m in "organization_memberships",
      where: m.organization_id == ^org and m.status == "active",
      where: fragment("? && ?::varchar[]", m.roles, ^@client_roles),
      select: {m.user_id, m.joined_at}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp visits(org, ids, now) do
    recent_from = DateTime.add(now, -28, :day)
    baseline_from = DateTime.add(now, -84, :day)

    from(a in "class_attendance_records",
      where: a.organization_id == ^org and a.user_id in ^ids and a.status == "attended",
      group_by: a.user_id,
      select:
        {a.user_id, fragment("count(*) FILTER (WHERE ? >= ?)", a.marked_at, ^recent_from),
         fragment(
           "count(*) FILTER (WHERE ? >= ? AND ? < ?)",
           a.marked_at,
           ^baseline_from,
           a.marked_at,
           ^recent_from
         ), max(a.marked_at)}
    )
    |> Repo.all()
    |> Map.new(fn {id, recent, baseline, last_at} -> {id, {recent, baseline, last_at}} end)
  end

  defp upcoming(org, ids, now) do
    until = DateTime.add(now, 14, :day)

    from(b in "bookings",
      join: c in "scheduled_classes",
      on: c.id == b.scheduled_class_id,
      where: b.organization_id == ^org and b.user_id in ^ids,
      where: b.status in ["approved", "pending"],
      where: c.scheduled_at >= ^now and c.scheduled_at < ^until and is_nil(c.cancelled_at),
      group_by: b.user_id,
      select: {b.user_id, count(b.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp cancellations(org, ids, now) do
    since = now |> DateTime.add(-28, :day) |> DateTime.to_naive()

    from(b in "bookings",
      where: b.organization_id == ^org and b.user_id in ^ids,
      where: b.status == "cancelled" and b.updated_at >= ^since,
      group_by: b.user_id,
      select: {b.user_id, count(b.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # The package that ends last of each person's active ones.
  defp packages(org, ids, today) do
    from(s in "membership_package_subscriptions",
      join: ms in "memberships",
      on: ms.id == s.membership_id,
      where: s.organization_id == ^org and ms.user_id in ^ids,
      where: s.status == "active" and not is_nil(s.ends_on) and s.ends_on >= ^today,
      order_by: [asc: ms.user_id, desc: s.ends_on],
      distinct: ms.user_id,
      select: {ms.user_id, s.ends_on, s.auto_renew}
    )
    |> Repo.all()
    |> Map.new(fn {id, ends_on, renews} -> {id, %{ends_on: ends_on, renews: renews == true}} end)
  end

  defp overdue(org, ids) do
    from(i in "finance_invoices",
      where: i.organization_id == ^org and i.user_id in ^ids and i.status == "overdue",
      where: is_nil(i.deleted_at),
      group_by: i.user_id,
      select: {i.user_id, count(i.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp to_date(%DateTime{} = at), do: DateTime.to_date(at)
  defp to_date(%NaiveDateTime{} = at), do: NaiveDateTime.to_date(at)
  defp to_date(%Date{} = date), do: date
end
