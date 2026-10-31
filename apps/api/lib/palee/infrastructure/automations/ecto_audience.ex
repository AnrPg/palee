defmodule Palee.Infrastructure.Automations.EctoAudience do
  @moduledoc """
  ADR-346: the daily recipes' read model over Scheduling (attendance),
  Organizations (who is an active box member) and Finance (subscription
  packages), in the box's scope. Reads only.
  """

  @behaviour Palee.Automations.Ports.Audience

  import Ecto.Query

  alias Palee.Repo

  @client_roles ~w(member athlete)

  @impl true
  def absent_members(%{organization_id: org_id}, %Date{} = today, days) do
    latest = Date.add(today, -days)
    earliest = Date.add(today, -(days + 30))
    {:ok, org} = Ecto.UUID.dump(org_id)

    visits =
      from(a in "class_attendance_records",
        where: a.organization_id == ^org and a.status == "attended",
        group_by: a.user_id,
        select: %{user_id: a.user_id, last_at: max(a.marked_at)}
      )

    from(v in subquery(visits),
      join: m in "organization_memberships",
      on: m.user_id == v.user_id and m.organization_id == ^org,
      where: m.status == "active" and fragment("? && ?::varchar[]", m.roles, ^@client_roles),
      select: {v.user_id, v.last_at}
    )
    |> Repo.all()
    |> Enum.flat_map(fn {user_id, last_at} ->
      last_on = last_at |> to_datetime() |> DateTime.to_date()

      if Date.compare(last_on, latest) != :gt and Date.compare(last_on, earliest) != :lt,
        do: [%{user_id: Ecto.UUID.load!(user_id), last_visit_on: last_on}],
        else: []
    end)
  end

  @impl true
  def ending_subscriptions(%{organization_id: org_id}, %Date{} = today, days) do
    until = Date.add(today, days)
    {:ok, org} = Ecto.UUID.dump(org_id)

    from(s in "membership_package_subscriptions",
      join: ms in "memberships",
      on: ms.id == s.membership_id,
      left_join: p in "membership_packages",
      on: p.id == s.membership_package_id,
      where: s.organization_id == ^org and s.status == "active",
      where: s.ends_on >= ^today and s.ends_on <= ^until,
      where: s.auto_renew == false,
      where:
        fragment(
          "NOT EXISTS (SELECT 1 FROM membership_package_subscriptions n WHERE n.membership_id = ? AND n.id <> ? AND n.status = 'active' AND n.starts_on > ?)",
          s.membership_id,
          s.id,
          s.starts_on
        ),
      select: %{
        user_id: ms.user_id,
        subscription_id: s.id,
        package_name: p.name,
        ends_on: s.ends_on
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | user_id: Ecto.UUID.load!(row.user_id), subscription_id: Ecto.UUID.load!(row.subscription_id)}
    end)
  end

  defp to_datetime(%DateTime{} = at), do: at
  defp to_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
