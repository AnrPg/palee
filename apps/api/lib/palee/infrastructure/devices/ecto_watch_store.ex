defmodule Palee.Infrastructure.Devices.EctoWatchStore do
  @moduledoc "Ecto adapter of the watch persistence port (ADR-375)."

  @behaviour Palee.Devices.Ports.WatchStore

  import Ecto.Query

  alias Palee.Devices.{HeartRateBatch, WatchLink}
  alias Palee.Repo

  @impl true
  def list_links(user_id) do
    WatchLink
    |> where([w], w.user_id == ^user_id)
    |> order_by([w], asc: w.platform)
    |> Repo.all()
  end

  @impl true
  def get_link(user_id, platform), do: Repo.get_by(WatchLink, user_id: user_id, platform: platform)

  @impl true
  def save_link(nil, attrs), do: attrs |> WatchLink.changeset() |> Repo.insert()
  def save_link(%WatchLink{} = link, attrs), do: link |> WatchLink.changeset(attrs) |> Repo.update()

  @impl true
  def delete_link(user_id, platform) do
    {count, _rows} =
      WatchLink
      |> where([w], w.user_id == ^user_id and w.platform == ^platform)
      |> Repo.delete_all()

    count
  end

  @impl true
  def insert_heart_rate(_execution_id, _user_id, [], _now), do: {:ok, 0}

  def insert_heart_rate(execution_id, user_id, rows, now) do
    entries =
      Enum.map(rows, fn row ->
        row
        |> Map.take([:platform, :sequence, :started_offset_ms, :interval_ms, :bpm])
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          execution_id: execution_id,
          user_id: user_id,
          inserted_at: now
        })
      end)

    {count, _rows} =
      Repo.insert_all(HeartRateBatch, entries,
        on_conflict: :nothing,
        conflict_target: [:execution_id, :sequence]
      )

    {:ok, count}
  end

  @impl true
  def list_heart_rate(execution_id) do
    HeartRateBatch
    |> where([b], b.execution_id == ^execution_id)
    |> order_by([b], asc: b.sequence)
    |> Repo.all()
  end
end
