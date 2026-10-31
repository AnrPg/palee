defmodule Palee.Infrastructure.Ranks.EctoRankStore do
  @moduledoc "Ecto adapter of the ranks persistence port (ADR-377)."

  @behaviour Palee.Ranks.Ports.RankStore

  import Ecto.Query

  alias Palee.Ranks.{Rank, RankAward, RankLadder}
  alias Palee.Repo

  @rank_fields [:position, :name, :color, :max_stripes, :requirements, :scale_level_slug]

  @impl true
  def list_ladders do
    RankLadder
    |> where([l], is_nil(l.archived_at))
    |> order_by([l], asc: l.position, asc: l.name)
    |> preload(:ranks)
    |> Repo.all()
  end

  @impl true
  def get_ladder(id) do
    RankLadder
    |> where([l], l.id == ^id and is_nil(l.archived_at))
    |> preload(:ranks)
    |> Repo.one()
  end

  @impl true
  def insert_ladder(attrs, ranks) do
    Repo.transaction(fn ->
      with {:ok, ladder} <- attrs |> RankLadder.changeset() |> Repo.insert(),
           :ok <- insert_ranks(ladder, ranks) do
        Repo.preload(ladder, :ranks, force: true)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def update_ladder(%RankLadder{} = ladder, attrs, ranks) do
    Repo.transaction(fn ->
      with {:ok, ladder} <- ladder |> RankLadder.changeset(attrs) |> Repo.update(),
           :ok <- replace_ranks(ladder, ranks) do
        Repo.preload(ladder, :ranks, force: true)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def archive_ladder(%RankLadder{} = ladder, now),
    do: ladder |> RankLadder.archive_changeset(now) |> Repo.update()

  defp insert_ranks(ladder, ranks) do
    now = DateTime.utc_now()

    entries =
      Enum.map(ranks, fn rank ->
        rank
        |> Map.take(@rank_fields)
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          organization_id: ladder.organization_id,
          ladder_id: ladder.id,
          inserted_at: now,
          updated_at: now
        })
      end)

    {_count, _rows} = Repo.insert_all(Rank, entries)
    :ok
  end

  # Kept ranks first move out of the way of the (ladder, position) index.
  defp replace_ranks(ladder, ranks) do
    existing = Rank |> where([r], r.ladder_id == ^ladder.id) |> Repo.all() |> Map.new(&{&1.id, &1})
    kept_ids = ranks |> Enum.map(& &1.id) |> Enum.filter(&Map.has_key?(existing, &1))
    removed = existing |> Map.keys() |> Kernel.--(kept_ids)

    with :ok <- delete_ranks(removed) do
      Rank
      |> where([r], r.id in ^kept_ids)
      |> Repo.update_all(inc: [position: 10_000])

      now = DateTime.utc_now()

      Enum.each(ranks, fn rank ->
        if rank.id in kept_ids do
          Rank
          |> where([r], r.id == ^rank.id)
          |> Repo.update_all(set: Keyword.new(Map.take(rank, @rank_fields)) ++ [updated_at: now])
        end
      end)

      insert_ranks(ladder, Enum.reject(ranks, &(&1.id in kept_ids)))
    end
  end

  defp delete_ranks([]), do: :ok

  defp delete_ranks(ids) do
    if RankAward |> where([a], a.rank_id in ^ids) |> Repo.exists?() do
      {:error, :rank_in_use}
    else
      Rank |> where([r], r.id in ^ids) |> Repo.delete_all()
      :ok
    end
  end

  @impl true
  def list_awards(user_id) do
    RankAward
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], desc: a.awarded_on, desc: a.inserted_at)
    |> Repo.all()
  end

  @impl true
  def get_award(id), do: Repo.get(RankAward, id)

  @impl true
  def insert_award(attrs), do: attrs |> RankAward.changeset() |> Repo.insert()

  @impl true
  def revoke_award(%RankAward{} = award, attrs),
    do: award |> RankAward.revoke_changeset(attrs) |> Repo.update()
end
