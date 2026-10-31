defmodule Palee.Infrastructure.Nutrition.EctoFoodStore do
  @moduledoc "Ecto adapter of the barcode foods port (ADR-376)."

  @behaviour Palee.Nutrition.Ports.FoodStore

  import Ecto.Query

  alias Palee.Nutrition.{CachedFood, CustomFood}
  alias Palee.Nutrition.Domain.FoodCachePolicy
  alias Palee.Repo

  @cache_fields ~w(status name brand quantity serving_size image_url categories nutrients
                   portion_hint attempts next_attempt_at claimed_at fetched_at last_error)a

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
