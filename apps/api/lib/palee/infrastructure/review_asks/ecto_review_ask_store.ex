defmodule Palee.Infrastructure.ReviewAsks.EctoReviewAskStore do
  @moduledoc "Ecto adapter of the review ask store (ADR-355)."

  @behaviour Palee.ReviewAsks.Ports.ReviewAskStore

  import Ecto.Query

  alias Palee.Repo

  alias Palee.ReviewAsks.{
    BoxReview,
    BoxReviewDecision,
    BoxReviewReport,
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
    :moderation,
    :moderated_at,
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
    |> where([r], r.organization_id == ^organization_id and is_nil(r.moderation))
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
      |> where([r], r.organization_id == ^organization_id and is_nil(r.moderation))
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

  # ── Reports and decisions (ADR-397) ─────────────────────────────────────

  @report_fields [
    :id,
    :organization_id,
    :review_id,
    :review_author_id,
    :reporter_id,
    :reporter_role,
    :reason,
    :note,
    :review_rating,
    :review_body,
    :status,
    :decision_id,
    :decided_at,
    :inserted_at
  ]

  @decision_fields [
    :id,
    :organization_id,
    :review_id,
    :review_author_id,
    :outcome,
    :ground,
    :statement,
    :reports_count,
    :decided_by_id,
    :decided_at
  ]

  @impl true
  def reported_review_ids(%{organization_id: organization_id}, reporter_id) do
    BoxReviewReport
    |> where(
      [r],
      r.organization_id == ^organization_id and r.reporter_id == ^reporter_id and
        r.status == "open"
    )
    |> select([r], r.review_id)
    |> Repo.all()
  end

  @impl true
  def count_reports_since(%{organization_id: organization_id}, reporter_id, since) do
    BoxReviewReport
    |> where(
      [r],
      r.organization_id == ^organization_id and r.reporter_id == ^reporter_id and
        r.inserted_at >= ^since
    )
    |> Repo.aggregate(:count)
  end

  @impl true
  def insert_report(%{organization_id: organization_id}, attrs) do
    %BoxReviewReport{organization_id: organization_id}
    |> BoxReviewReport.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, report} ->
        {:ok, Map.take(report, @report_fields)}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Enum.any?(errors, fn {_field, {message, _meta}} -> message == "already_reported" end),
          do: {:error, :already_reported},
          else: {:error, changeset}
    end
  end

  @impl true
  def latest_decision(%{organization_id: organization_id}, review_id) do
    BoxReviewDecision
    |> where([d], d.organization_id == ^organization_id and d.review_id == ^review_id)
    |> order_by([d], desc: d.decided_at, desc: d.id)
    |> limit(1)
    |> Repo.one()
    |> decision_map()
  end

  @impl true
  def decide_review(%{organization_id: organization_id}, review_id, changes, decision, status) do
    Repo.transaction(fn ->
      review =
        Repo.one(
          from r in BoxReview,
            where: r.organization_id == ^organization_id and r.id == ^review_id,
            lock: "FOR UPDATE"
        ) || Repo.rollback(:box_review_not_found)

      open =
        Repo.all(
          from r in BoxReviewReport,
            where:
              r.organization_id == ^organization_id and r.review_id == ^review_id and
                r.status == "open",
            lock: "FOR UPDATE"
        )

      if open == [], do: Repo.rollback(:review_report_decided)

      updated = review |> Ecto.Changeset.change(changes) |> Repo.update!()

      saved =
        %BoxReviewDecision{organization_id: organization_id}
        |> BoxReviewDecision.changeset(
          Map.merge(decision, %{
            review_id: review.id,
            review_author_id: review.user_id,
            reports_count: length(open)
          })
        )
        |> Repo.insert!()

      ids = Enum.map(open, & &1.id)

      {_count, reports} =
        Repo.update_all(
          from(r in BoxReviewReport, where: r.id in ^ids, select: r),
          set: [
            status: status,
            decision_id: saved.id,
            decided_at: saved.decided_at,
            updated_at: saved.decided_at
          ]
        )

      %{
        review: review_map(updated),
        decision: decision_map(saved),
        reports: Enum.map(reports, &Map.take(&1, @report_fields))
      }
    end)
  end

  # The Palee team's reads span every box: the vendor read policy admits
  # them, the session has no organization.
  @impl true
  def platform_open_reports(_context, limit) do
    BoxReviewReport
    |> where([r], r.status == "open")
    |> order_by([r], asc: r.inserted_at, asc: r.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&Map.take(&1, @report_fields))
  end

  @impl true
  def platform_decisions(_context, limit) do
    BoxReviewDecision
    |> order_by([d], desc: d.decided_at, desc: d.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&decision_map/1)
  end

  @impl true
  def platform_review_organization(_context, review_id) do
    case Ecto.UUID.cast(review_id) do
      {:ok, id} ->
        BoxReviewReport
        |> where([r], r.review_id == ^id)
        |> select([r], r.organization_id)
        |> limit(1)
        |> Repo.one()

      :error ->
        nil
    end
  end

  defp decision_map(nil), do: nil
  defp decision_map(decision), do: Map.take(decision, @decision_fields)

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
