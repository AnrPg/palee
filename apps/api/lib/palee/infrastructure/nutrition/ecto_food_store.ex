defmodule Palee.Infrastructure.Nutrition.EctoFoodStore do
  @moduledoc "Ecto adapter of the barcode foods port (ADR-376)."

  @behaviour Palee.Nutrition.Ports.FoodStore

  import Ecto.Query

  alias Palee.Nutrition.{BarcodeMiss, CachedFood, CustomFood, FoodShare}
  alias Palee.Nutrition.Domain.{FoodCachePolicy, FoodSharePolicy}
  alias Palee.Repo

  @cache_fields ~w(status source name brand quantity serving_size image_url categories nutrients
                   portion_hint attribution attempts next_attempt_at claimed_at fetched_at
                   last_error)a

  @impl true
  def get_cached(barcode), do: Repo.get(CachedFood, barcode)

  @impl true
  def request_lookup(barcode, now) do
    Repo.insert_all(
      CachedFood,
      [
        %{
          barcode: barcode,
          status: "pending",
          next_attempt_at: now,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [set: [status: "pending", next_attempt_at: now, attempts: 0, updated_at: now]],
      conflict_target: [:barcode]
    )

    :ok
  end

  @impl true
  def claim(which, now, limit) do
    stale = DateTime.add(now, -FoodCachePolicy.claim_timeout_seconds(), :second)

    candidates =
      CachedFood
      |> where(
        [f],
        f.status == "pending" and
          ((is_nil(f.claimed_at) and f.next_attempt_at <= ^now) or f.claimed_at < ^stale)
      )
      |> then(fn query ->
        case which do
          :due -> query
          barcode -> where(query, [f], f.barcode == ^barcode)
        end
      end)
      |> order_by([f], asc: f.next_attempt_at)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([f], f.barcode)

    {_count, rows} =
      CachedFood
      |> where([f], f.barcode in subquery(candidates))
      |> select([f], f)
      |> Repo.update_all(set: [claimed_at: now, updated_at: now], inc: [attempts: 1])

    rows
  end

  @impl true
  def finish(barcode, changes, now) do
    case Repo.get(CachedFood, barcode) do
      nil ->
        {:error, :not_found}

      row ->
        row
        |> Ecto.Changeset.change(Map.take(changes, @cache_fields))
        |> Ecto.Changeset.put_change(:updated_at, now)
        |> Repo.update()
    end
  end

  @impl true
  def record_miss(barcode, country, date) do
    Repo.insert_all(
      BarcodeMiss,
      [%{barcode: barcode, country: country, scans: 1, first_seen_on: date, last_seen_on: date}],
      on_conflict:
        from(m in BarcodeMiss,
          update: [
            inc: [scans: 1],
            set: [last_seen_on: fragment("GREATEST(?, EXCLUDED.last_seen_on)", m.last_seen_on)]
          ]
        ),
      conflict_target: [:barcode, :country]
    )

    :ok
  end

  @impl true
  def list_misses(country, limit) do
    BarcodeMiss
    |> then(fn query ->
      if is_binary(country), do: where(query, [m], m.country == ^country), else: query
    end)
    |> order_by([m], desc: m.scans, desc: m.last_seen_on, asc: m.barcode)
    |> limit(^limit)
    |> Repo.all()
  end

  # ADR-421 addendum: a members' row replaces only a row where no source has
  # the product (nothing found, or a lookup with nothing yet); a found
  # product, a stale one being refreshed and an earlier share all stay.
  @share_cache_fields ~w(status source name brand quantity serving_size image_url categories
                         nutrients portion_hint attribution attempts next_attempt_at claimed_at
                         fetched_at last_error updated_at)a

  @impl true
  def share_product(share, cache) do
    {:ok, result} =
      Repo.transaction(fn ->
        {count, _rows} =
          Repo.insert_all(CachedFood, [cache],
            on_conflict:
              from(f in CachedFood,
                where: f.status != "found" and (f.status == "not_found" or is_nil(f.name)),
                update: [set: ^Enum.map(@share_cache_fields, &{&1, Map.fetch!(cache, &1)})]
              ),
            conflict_target: [:barcode]
          )

        if count == 1 do
          Repo.insert_all(FoodShare, [share], on_conflict: :nothing, conflict_target: [:barcode])
          :shared
        else
          :exists
        end
      end)

    result
  end

  @impl true
  def claim_shares(now, limit) do
    stale = DateTime.add(now, -FoodSharePolicy.claim_timeout_seconds(), :second)

    candidates =
      FoodShare
      |> where(
        [s],
        s.off_status == "queued" and
          ((is_nil(s.off_claimed_at) and s.off_next_attempt_at <= ^now) or
             s.off_claimed_at < ^stale)
      )
      |> order_by([s], asc: s.off_next_attempt_at)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([s], s.barcode)

    {_count, rows} =
      FoodShare
      |> where([s], s.barcode in subquery(candidates))
      |> select([s], s)
      |> Repo.update_all(set: [off_claimed_at: now, updated_at: now], inc: [off_attempts: 1])

    rows
  end

  @impl true
  def finish_share(barcode, changes, now) do
    set =
      changes
      |> Map.take(~w(off_status off_next_attempt_at off_claimed_at off_sent_at off_last_error)a)
      |> Map.put(:updated_at, now)
      |> Enum.to_list()

    FoodShare |> where([s], s.barcode == ^barcode) |> Repo.update_all(set: set)
    :ok
  end

  @impl true
  def list_custom_foods(user_id) do
    CustomFood
    |> where([f], f.user_id == ^user_id)
    |> order_by([f], asc: fragment("lower(?)", f.name))
    |> Repo.all()
  end

  @impl true
  def get_custom_food(id, user_id), do: Repo.get_by(CustomFood, id: id, user_id: user_id)

  @impl true
  def custom_food_by_barcode(user_id, barcode),
    do: Repo.get_by(CustomFood, user_id: user_id, barcode: barcode)

  @impl true
  def insert_custom_food(attrs), do: attrs |> CustomFood.changeset() |> Repo.insert()

  @impl true
  def update_custom_food(%CustomFood{} = food, attrs),
    do: food |> CustomFood.changeset(attrs) |> Repo.update()

  @impl true
  def delete_custom_food(%CustomFood{} = food) do
    {:ok, _deleted} = Repo.delete(food)
    :ok
  end
end
