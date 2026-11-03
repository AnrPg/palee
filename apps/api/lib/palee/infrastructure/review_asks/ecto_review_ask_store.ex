defmodule Palee.Infrastructure.ReviewAsks.EctoReviewAskStore do
  @moduledoc "Ecto adapter of the review ask store (ADR-355)."

  @behaviour Palee.ReviewAsks.Ports.ReviewAskStore

  import Ecto.Query

  alias Palee.Repo

  alias Palee.ReviewAsks.{
    BoxReview,
    GooglePlaceSnapshot,
    ReviewAsk,
    ReviewAskOptOut,
    ReviewAskSettings
  }

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

  # ── In-app reviews (ADR-386) ────────────────────────────────────────────

  @review_fields [
    :id,
    :user_id,
    :rating,
    :body,
    :locale,
    :edited_at,
    :reply_body,
    :replied_at,
    :replied_by_id,
    :inserted_at,
    :updated_at
  ]

  @impl true
  def get_review(%{organization_id: organization_id}, user_id) do
    BoxReview
    |> where([r], r.organization_id == ^organization_id and r.user_id == ^user_id)
    |> Repo.one()
    |> review_map()
  end

  @impl true
  def get_review_by_id(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        BoxReview
        |> where([r], r.organization_id == ^organization_id and r.id == ^id)
        |> Repo.one()
        |> review_map()

      :error ->
        nil
    end
  end

  @impl true
  def save_review(%{organization_id: organization_id}, user_id, attrs) do
    row =
      Repo.one(
        from r in BoxReview,
          where: r.organization_id == ^organization_id and r.user_id == ^user_id
      )

    (row || %BoxReview{organization_id: organization_id})
    |> BoxReview.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert_or_update()
    |> case do
      {:ok, review} -> {:ok, review_map(review)}
      error -> error
    end
  end

  @impl true
  def delete_review(%{organization_id: organization_id}, user_id) do
    BoxReview
    |> where([r], r.organization_id == ^organization_id and r.user_id == ^user_id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def list_reviews(%{organization_id: organization_id}, %{limit: limit, offset: offset}) do
    BoxReview
    |> where([r], r.organization_id == ^organization_id)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> Enum.map(&review_map/1)
  end

  @impl true
  def review_stats(%{organization_id: organization_id}) do
    {count, sum} =
      BoxReview
      |> where([r], r.organization_id == ^organization_id)
      |> select([r], {count(r.id), coalesce(sum(r.rating), 0)})
      |> Repo.one()

    %{count: count, sum: to_integer(sum)}
  end

  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value

  @impl true
  def reply_review(%{organization_id: organization_id}, id, attrs) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %BoxReview{} = review <-
           Repo.one(
             from r in BoxReview, where: r.organization_id == ^organization_id and r.id == ^id
           ) do
      review
      |> BoxReview.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, review} -> {:ok, review_map(review)}
        error -> error
      end
    else
      _missing -> {:error, :box_review_not_found}
    end
  end

  defp review_map(nil), do: nil
  defp review_map(review), do: Map.take(review, @review_fields)

  # ── Google listing (ADR-387) ────────────────────────────────────────────

  @impl true
  def get_place_snapshot(%{organization_id: organization_id}) do
    GooglePlaceSnapshot
    |> where([g], g.organization_id == ^organization_id)
    |> Repo.one()
    |> snapshot_map()
  end

  @impl true
  def save_place_snapshot(%{organization_id: organization_id}, attrs) do
    row =
      Repo.one(from g in GooglePlaceSnapshot, where: g.organization_id == ^organization_id)

    (row || %GooglePlaceSnapshot{organization_id: organization_id})
    |> GooglePlaceSnapshot.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, snapshot} -> {:ok, snapshot_map(snapshot)}
      error -> error
    end
  end

  @impl true
  def place_due_organizations(now) do
    %{rows: rows} =
      Repo.query!("SELECT organization_id FROM palee_google_place_due_organizations($1)", [now])

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end

  defp snapshot_map(nil), do: nil

  defp snapshot_map(snapshot) do
    Map.take(snapshot, [
      :place_id,
      :name,
      :rating,
      :rating_count,
      :maps_uri,
      :status,
      :fetched_at,
      :next_refresh_at,
      :attempts
    ])
  end
end
