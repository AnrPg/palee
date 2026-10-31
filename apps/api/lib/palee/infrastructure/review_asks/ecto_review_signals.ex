defmodule Palee.Infrastructure.ReviewAsks.EctoReviewSignals do
  @moduledoc """
  ADR-355: the behavioural facts behind a review ask, read from the box's
  own tables in its tenant session (attended classes, membership,
  member since). A read model: it never writes.
  """

  @behaviour Palee.ReviewAsks.Ports.ReviewSignals

  import Ecto.Query

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def facts(%{organization_id: organization_id} = context, user_id) do
    RepoContext.run(context, fn ->
      org = Ecto.UUID.dump!(organization_id)
      user = Ecto.UUID.dump!(user_id)

      {count, last} =
        from(r in "class_attendance_records",
          where: r.organization_id == ^org and r.user_id == ^user and r.status == "attended",
          select: {count(r.id), max(r.marked_at)}
        )
        |> Repo.one()

      active =
        from(m in "memberships",
          where: m.organization_id == ^org and m.user_id == ^user and m.status == "active"
        )
        |> Repo.exists?()

      since =
        from(m in "organization_memberships",
          where: m.organization_id == ^org and m.user_id == ^user,
          select: min(m.joined_at)
        )
        |> Repo.one()

      %{
        active_membership: active,
        member_since: datetime(since),
        attendance_count: count || 0,
        last_attended_at: datetime(last)
      }
    end)
  end

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = at), do: at
  defp datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
