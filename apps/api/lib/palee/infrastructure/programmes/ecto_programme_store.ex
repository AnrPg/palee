defmodule Palee.Infrastructure.Programmes.EctoProgrammeStore do
  @moduledoc "Ecto adapter of programmes, versions, purchases, deliveries and reviews (ADR-370/371)."

  @behaviour Palee.Programmes.Ports.ProgrammeStore

  import Ecto.Query

  alias Palee.Programmes.{
    Programme,
    ProgrammeDelivery,
    ProgrammePurchase,
    ProgrammeReview,
    ProgrammeVersion
  }

  alias Palee.Repo

  @impl true
  def transaction(_context, fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Programmes ──────────────────────────────────────────────────────────

  @impl true
  def create_programme(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Programme.create_changeset()
    |> Repo.insert()
  end

  @impl true
  def update_programme(_context, programme, attrs),
    do: programme |> Programme.update_changeset(attrs) |> Repo.update()

  @impl true
  def set_state(_context, programme, changes),
    do: programme |> Programme.state_changeset(changes) |> Repo.update()

  @impl true
  def set_cover(_context, programme, changes),
    do: programme |> Programme.cover_changeset(changes) |> Repo.update()

  @impl true
  def cover_in_use?(_context, [], _except_id), do: false

  def cover_in_use?(%{organization_id: organization_id}, media_ids, except_id) do
    Repo.exists?(
      from p in Programme,
        where:
          p.organization_id == ^organization_id and p.id != ^except_id and
            (p.cover_media_id in ^media_ids or p.cover_original_media_id in ^media_ids)
    )
  end

  @impl true
  def get_programme(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.one(from p in Programme, where: p.id == ^id and p.organization_id == ^organization_id)
    else
      :error -> nil
    end
  end

  @impl true
  def list_programmes(%{organization_id: organization_id}, filters) do
    Programme
    |> where([p], p.organization_id == ^organization_id)
    |> filter_in(:status, Map.get(filters, :statuses))
    |> filter_in(:listing, Map.get(filters, :listings))
    |> order_by([p], desc: p.updated_at, desc: p.id)
    |> limit(200)
    |> Repo.all()
  end

  defp filter_in(query, _field, nil), do: query
  defp filter_in(query, field, values), do: where(query, [p], field(p, ^field) in ^values)

  @impl true
  def publish_version(%{organization_id: organization_id}, programme_id, version_attrs, changes) do
    Repo.transaction(fn ->
      programme =
        Repo.one(
          from p in Programme,
            where: p.id == ^programme_id and p.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        ) || Repo.rollback(:not_found)

      number =
        (Repo.one(
           from v in ProgrammeVersion,
             where: v.programme_id == ^programme_id,
             select: max(v.number)
         ) || 0) + 1

      version =
        version_attrs
        |> Map.merge(%{
          organization_id: organization_id,
          programme_id: programme_id,
          number: number
        })
        |> ProgrammeVersion.create_changeset()
        |> Repo.insert()
        |> ok_or_rollback()

      programme =
        programme
        |> Programme.state_changeset(Map.put(changes, :current_version_id, version.id))
        |> Repo.update()
        |> ok_or_rollback()

      %{programme: programme, version: version}
    end)
  end

  @impl true
  def get_version(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.one(
        from v in ProgrammeVersion, where: v.id == ^id and v.organization_id == ^organization_id
      )
    else
      :error -> nil
    end
  end

  @impl true
  def list_versions(%{organization_id: organization_id}, programme_id) do
    Repo.all(
      from v in ProgrammeVersion,
        where: v.organization_id == ^organization_id and v.programme_id == ^programme_id,
        order_by: [desc: v.number]
    )
  end

  # ── Purchases ───────────────────────────────────────────────────────────

  @impl true
  def create_purchase(%{organization_id: organization_id} = context, attrs) do
    attrs = Map.put(attrs, :organization_id, organization_id)

    case attrs |> ProgrammePurchase.create_changeset() |> Repo.insert() do
      {:ok, purchase} ->
        {:ok, purchase}

      {:error, %Ecto.Changeset{} = changeset} = error ->
        if Keyword.has_key?(changeset.errors, :organization_id),
          do: by_key(context, attrs.idempotency_key, error),
          else: error
    end
  end

  defp by_key(%{organization_id: organization_id}, key, error) do
    case Repo.one(
           from p in ProgrammePurchase,
             where: p.organization_id == ^organization_id and p.idempotency_key == ^key
         ) do
      nil -> error
      purchase -> {:ok, purchase}
    end
  end

  @impl true
  def get_purchase(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.one(
        from p in ProgrammePurchase, where: p.id == ^id and p.organization_id == ^organization_id
      )
    else
      :error -> nil
    end
  end

  @impl true
  def purchase_by_intent(%{organization_id: organization_id}, intent_id) do
    Repo.one(
      from p in ProgrammePurchase,
        where: p.organization_id == ^organization_id and p.payment_intent_id == ^intent_id
    )
  end

  @impl true
  def open_purchase(%{organization_id: organization_id}, programme_id, user_id) do
    Repo.one(
      from p in ProgrammePurchase,
        where:
          p.organization_id == ^organization_id and p.programme_id == ^programme_id and
            p.user_id == ^user_id and p.status == "active",
        limit: 1
    )
  end

  @impl true
  def set_purchase_intent(context, id, intent_id) do
    case get_purchase(context, id) do
      nil -> {:error, :not_found}
      purchase -> purchase |> ProgrammePurchase.payment_changeset(intent_id) |> Repo.update()
    end
  end

  @impl true
  def update_purchase(%{organization_id: organization_id}, id, decide) do
    Repo.transaction(fn ->
      purchase =
        Repo.one(
          from p in ProgrammePurchase,
            where: p.id == ^id and p.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        ) || Repo.rollback(:not_found)

      case decide.(purchase) do
        {:ok, changes} when changes == %{} ->
          purchase

        {:ok, changes} ->
          purchase
          |> ProgrammePurchase.transition_changeset(changes)
          |> Repo.update()
          |> ok_or_rollback()

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def update_schedule(%{organization_id: organization_id}, id, decide) do
    Repo.transaction(fn ->
      purchase =
        Repo.one(
          from p in ProgrammePurchase,
            where: p.id == ^id and p.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        ) || Repo.rollback(:not_found)

      case decide.(purchase) do
        {:ok, changes} when changes == %{} ->
          purchase

        {:ok, changes} ->
          purchase
          |> ProgrammePurchase.schedule_changeset(changes)
          |> Repo.update()
          |> ok_or_rollback()

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def list_purchases(%{organization_id: organization_id}, filters) do
    ProgrammePurchase
    |> where([p], p.organization_id == ^organization_id)
    |> maybe_where(:programme_id, Map.get(filters, :programme_id))
    |> maybe_where(:user_id, Map.get(filters, :user_id))
    |> purchase_statuses(Map.get(filters, :statuses))
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^min(Map.get(filters, :limit, 200), 500))
    |> Repo.all()
  end

  defp maybe_where(query, _field, nil), do: query
  defp maybe_where(query, field, value), do: where(query, [p], field(p, ^field) == ^value)

  defp purchase_statuses(query, nil), do: query
  defp purchase_statuses(query, statuses), do: where(query, [p], p.status in ^statuses)

  @impl true
  def due_completions(%{organization_id: organization_id}, today) do
    Repo.all(
      from p in ProgrammePurchase,
        where:
          p.organization_id == ^organization_id and p.status == "active" and
            p.ends_on < ^today,
        limit: 500
    )
  end

  @impl true
  def sales(_context, []), do: %{}

  def sales(%{organization_id: organization_id}, programme_ids) do
    from(p in ProgrammePurchase,
      where: p.organization_id == ^organization_id and p.programme_id in ^programme_ids,
      where: p.status in ["active", "completed", "withdrawn", "refunded"],
      group_by: [p.programme_id, p.currency],
      select:
        {p.programme_id,
         %{
           currency: p.currency,
           buyers: count(p.id),
           active: filter(count(p.id), p.status == "active"),
           gross_cents: sum(p.price_cents),
           refunded_cents: sum(p.refunded_cents)
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ── Deliveries ──────────────────────────────────────────────────────────

  @impl true
  def record_deliveries(_context, _purchase_id, _user_id, []), do: :ok

  def record_deliveries(%{organization_id: organization_id}, purchase_id, user_id, rows) do
    now = DateTime.utc_now()

    entries =
      Enum.map(rows, fn row ->
        %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          purchase_id: purchase_id,
          user_id: user_id,
          assigned_workout_id: row.assigned_workout_id,
          day: row.day,
          scheduled_for: row.scheduled_for,
          inserted_at: now
        }
      end)

    Repo.insert_all(ProgrammeDelivery, entries, on_conflict: :nothing)
    :ok
  end

  @impl true
  def deliveries(%{organization_id: organization_id}, purchase_id, from_date) do
    ProgrammeDelivery
    |> where([d], d.organization_id == ^organization_id and d.purchase_id == ^purchase_id)
    |> then(fn query ->
      if from_date, do: where(query, [d], d.scheduled_for >= ^from_date), else: query
    end)
    |> order_by([d], asc: d.scheduled_for, asc: d.day)
    |> Repo.all()
  end

  @impl true
  def delete_deliveries(%{organization_id: organization_id}, purchase_id, from_date) do
    {count, _} =
      Repo.delete_all(
        from d in ProgrammeDelivery,
          where:
            d.organization_id == ^organization_id and d.purchase_id == ^purchase_id and
              d.scheduled_for >= ^from_date
      )

    count
  end

  @impl true
  def move_deliveries(_context, _purchase_id, []), do: :ok

  def move_deliveries(%{organization_id: organization_id}, purchase_id, moves) do
    Enum.each(moves, fn {id, date} ->
      Repo.update_all(
        from(d in ProgrammeDelivery,
          where:
            d.id == ^id and d.organization_id == ^organization_id and
              d.purchase_id == ^purchase_id
        ),
        set: [scheduled_for: date]
      )
    end)
  end

  # ── Reviews ─────────────────────────────────────────────────────────────

  @impl true
  def save_review(%{organization_id: organization_id} = context, purchase, attrs) do
    review = review_for_purchase(context, purchase.id) || %ProgrammeReview{}

    review
    |> ProgrammeReview.changeset(
      Map.merge(attrs, %{
        organization_id: organization_id,
        programme_id: purchase.programme_id,
        purchase_id: purchase.id,
        user_id: purchase.user_id
      })
    )
    |> Repo.insert_or_update()
  end

  @impl true
  def get_review(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.one(
        from r in ProgrammeReview, where: r.id == ^id and r.organization_id == ^organization_id
      )
    else
      :error -> nil
    end
  end

  @impl true
  def review_for_purchase(%{organization_id: organization_id}, purchase_id) do
    Repo.one(
      from r in ProgrammeReview,
        where: r.organization_id == ^organization_id and r.purchase_id == ^purchase_id
    )
  end

  @impl true
  def list_reviews(%{organization_id: organization_id}, programme_id, filters) do
    ProgrammeReview
    |> where([r], r.organization_id == ^organization_id and r.programme_id == ^programme_id)
    |> then(fn query ->
      if Map.get(filters, :published_only, false),
        do: where(query, [r], r.status == "published"),
        else: query
    end)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(^min(Map.get(filters, :limit, 50), 200))
    |> Repo.all()
  end

  @impl true
  def moderate_review(_context, review, changes),
    do: review |> ProgrammeReview.moderation_changeset(changes) |> Repo.update()

  @impl true
  def review_summaries(_context, []), do: %{}

  def review_summaries(%{organization_id: organization_id}, programme_ids) do
    from(r in ProgrammeReview,
      where:
        r.organization_id == ^organization_id and r.programme_id in ^programme_ids and
          r.status == "published",
      group_by: r.programme_id,
      select: {r.programme_id, %{average: avg(r.rating), count: count(r.id)}}
    )
    |> Repo.all()
    |> Map.new(fn {id, %{average: average} = summary} ->
      {id, %{summary | average: average && Float.round(Decimal.to_float(average), 1)}}
    end)
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
