defmodule Palee.Infrastructure.Organizations.EctoFollowerInviteStore do
  @moduledoc """
  ADR-580: a box's invitations to its followers in Postgres (RLS by box;
  the person reads their own). Who follows the box comes from the SECURITY
  DEFINER functions `palee_box_followers` and `palee_box_follower_counts`,
  bound to the box in scope.
  """

  @behaviour Palee.Organizations.Ports.FollowerInviteStore

  import Ecto.Query

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.FollowerInvitePolicy
  alias Palee.Organizations.FollowerInvite
  alias Palee.Repo

  @impl true
  def list_followers(filter, limit, before, now) do
    {before_at, before_id} =
      case before do
        {%DateTime{} = at, id} when is_binary(id) -> {at, Ecto.UUID.dump!(id)}
        _none -> {nil, nil}
      end

    followers(filter, limit, before_at, before_id, nil, now)
  end

  @impl true
  def followers_among([], _now), do: %{}

  def followers_among(user_ids, now) do
    ids = Enum.flat_map(user_ids, &dump/1)

    "all"
    |> followers(length(ids), nil, nil, ids, now)
    |> Map.new(&{&1.user_id, &1})
  end

  defp followers(filter, limit, before_at, before_id, among, now) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT user_id, followed_at, former_member, had_trial, invite_status, invited_at, invitable
        FROM palee_box_followers($1::text, $2::integer, $3::timestamptz, $4::uuid, $5::timestamptz, $6::uuid[])
        """,
        [filter, limit, before_at, before_id, FollowerInvitePolicy.reinvite_before(now), among]
      )

    Enum.map(rows, fn [id, followed_at, former, trial, status, invited_at, invitable] ->
      %{
        user_id: Ecto.UUID.load!(id),
        followed_at: followed_at,
        former_member: former,
        had_trial: trial,
        invite_status: status,
        invited_at: invited_at,
        invitable: invitable
      }
    end)
  end

  @impl true
  def counts(now) do
    %{rows: [[listed, invitable, trial, former]]} =
      Repo.query!(
        "SELECT listed, invitable, trial, former FROM palee_box_follower_counts($1::timestamptz)",
        [
          FollowerInvitePolicy.reinvite_before(now)
        ]
      )

    %{listed: listed, invitable: invitable, trial: trial, former: former}
  end

  @impl true
  def create_many(user_ids, content, now) do
    rows =
      Enum.map(user_ids, fn user_id ->
        %{
          id: Ecto.UUID.generate(),
          organization_id: box_id(),
          user_id: user_id,
          invited_by_id: content.invited_by_id,
          message: content.message,
          package_id: content.package_id,
          offer_trial: content.offer_trial,
          status: "sent",
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all(FollowerInvite, rows, returning: true) do
      {_count, invites} -> {:ok, Enum.map(invites, &normalize/1)}
    end
  rescue
    error in [Postgrex.Error, Ecto.ConstraintError] -> {:error, error}
  end

  @impl true
  def latest_for(user_id) do
    FollowerInvite
    |> box_scope()
    |> where([i], i.user_id == ^user_id)
    |> order_by([i], desc: i.status == "declined", desc: i.inserted_at, desc: i.id)
    |> limit(1)
    |> Repo.one()
    |> normalize()
  end

  @impl true
  def decline(user_id, now) do
    Repo.transaction(fn ->
      open =
        FollowerInvite
        |> box_scope()
        |> where([i], i.user_id == ^user_id and i.status == "sent")
        |> lock("FOR UPDATE")
        |> Repo.all()

      Enum.reduce(open, nil, fn invite, _last ->
        case invite |> FollowerInvite.decline_changeset(now) |> Repo.update() do
          {:ok, declined} -> normalize(declined)
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  defp box_id, do: RepoContext.current_setting("app.organization_id")

  defp box_scope(queryable) do
    case box_id() do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _ ->
        from(row in queryable, where: false)
    end
  end

  defp dump(id) do
    case Ecto.UUID.dump(id) do
      {:ok, raw} -> [raw]
      :error -> []
    end
  end

  defp normalize(nil), do: nil

  defp normalize(%FollowerInvite{} = invite),
    do: invite |> Map.from_struct() |> Map.drop([:__meta__])
end
