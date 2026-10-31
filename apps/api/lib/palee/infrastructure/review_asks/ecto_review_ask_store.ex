defmodule Palee.Infrastructure.ReviewAsks.EctoReviewAskStore do
  @moduledoc "Ecto adapter of the review ask store (ADR-355)."

  @behaviour Palee.ReviewAsks.Ports.ReviewAskStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.ReviewAsks.{ReviewAsk, ReviewAskOptOut, ReviewAskSettings}

  @impl true
  def get_settings(%{organization_id: organization_id}) do
    organization_id |> settings_row() |> settings_map()
  end

  @impl true
  def save_settings(%{organization_id: organization_id}, changes, lock_version) do
    case settings_row(organization_id) do
      nil when lock_version in [0, nil] ->
        %ReviewAskSettings{organization_id: organization_id}
        |> ReviewAskSettings.changeset(changes)
        |> Repo.insert()

      %ReviewAskSettings{lock_version: ^lock_version} = row ->
        row |> ReviewAskSettings.changeset(changes) |> Repo.update()

      _other ->
        {:error, :stale}
    end
    |> case do
      {:ok, row} -> {:ok, settings_map(row)}
      error -> error
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  defp settings_row(organization_id),
    do: Repo.one(from s in ReviewAskSettings, where: s.organization_id == ^organization_id)

  defp settings_map(nil), do: nil

  defp settings_map(row),
    do: Map.take(row, [:google_place_id, :enabled, :milestones, :lock_version, :updated_at])

  @impl true
  def list_asks(%{organization_id: organization_id}, user_id) do
    ReviewAsk
    |> where([a], a.organization_id == ^organization_id and a.user_id == ^user_id)
    |> order_by([a], desc: a.shown_at)
    |> Repo.all()
    |> Enum.map(&ask_map/1)
  end

  @impl true
  def insert_ask(%{organization_id: organization_id}, attrs) do
    %ReviewAsk{organization_id: organization_id}
    |> ReviewAsk.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, ask} -> {:ok, ask_map(ask)}
      {:error, %Ecto.Changeset{errors: [{:organization_id, _} | _]}} -> {:error, :already_asked}
      error -> error
    end
  end

  @impl true
  def get_ask(%{organization_id: organization_id}, id, user_id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %ReviewAsk{} = ask <-
           Repo.one(
             from a in ReviewAsk,
               where:
                 a.organization_id == ^organization_id and a.id == ^id and a.user_id == ^user_id
           ) do
      ask_map(ask)
    else
      _missing -> nil
    end
  end

  @impl true
  def update_ask(%{organization_id: organization_id}, id, changes) do
    case Repo.one(
           from a in ReviewAsk, where: a.organization_id == ^organization_id and a.id == ^id
         ) do
      nil ->
        {:error, :review_ask_not_found}

      ask ->
        ask
        |> ReviewAsk.changeset(changes)
        |> Repo.update()
        |> case do
          {:ok, ask} -> {:ok, ask_map(ask)}
          error -> error
        end
    end
  end

  defp ask_map(ask),
    do: Map.take(ask, [:id, :user_id, :trigger, :milestone, :status, :shown_at, :responded_at])

  @impl true
  def opted_out?(%{organization_id: organization_id}, user_id) do
    Repo.exists?(
      from o in ReviewAskOptOut,
        where: o.organization_id == ^organization_id and o.user_id == ^user_id
    )
  end

  @impl true
  def opt_out(%{organization_id: organization_id}, user_id, now) do
    Repo.insert!(
      %ReviewAskOptOut{organization_id: organization_id, user_id: user_id, opted_out_at: now},
      on_conflict: :nothing,
      conflict_target: [:organization_id, :user_id]
    )

    :ok
  end

  @impl true
  def opt_in(%{organization_id: organization_id}, user_id) do
    ReviewAskOptOut
    |> where([o], o.organization_id == ^organization_id and o.user_id == ^user_id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def summary(%{organization_id: organization_id}, since) do
    by_status =
      ReviewAsk
      |> where([a], a.organization_id == ^organization_id and a.shown_at >= ^since)
      |> group_by([a], a.status)
      |> select([a], {a.status, count(a.id)})
      |> Repo.all()
      |> Map.new()

    opted_out =
      ReviewAskOptOut
      |> where([o], o.organization_id == ^organization_id and o.opted_out_at >= ^since)
      |> Repo.aggregate(:count)

    %{
      asked: by_status |> Map.values() |> Enum.sum(),
      opened: Map.get(by_status, "opened", 0),
      later: Map.get(by_status, "later", 0),
      dismissed: Map.get(by_status, "dismissed", 0),
      unanswered: Map.get(by_status, "shown", 0),
      opted_out: opted_out
    }
  end
end
