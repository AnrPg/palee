defmodule Palee.Nutrition.FoodStore do
  @moduledoc "Dispatches the barcode foods port to the configured adapter (ADR-376)."

  @behaviour Palee.Nutrition.Ports.FoodStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  @doc "Runs custom-food calls in the person's own session."
  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def get_cached(barcode), do: adapter().get_cached(barcode)
  @impl true
  def request_lookup(barcode, now), do: adapter().request_lookup(barcode, now)
  @impl true
  def claim(which, now, limit), do: adapter().claim(which, now, limit)
  @impl true
  def finish(barcode, changes, now), do: adapter().finish(barcode, changes, now)

  @impl true
  def record_miss(barcode, country, date), do: adapter().record_miss(barcode, country, date)
  @impl true
  def list_misses(country, limit), do: adapter().list_misses(country, limit)

  @impl true
  def share_product(share, cache), do: adapter().share_product(share, cache)
  @impl true
  def claim_shares(now, limit), do: adapter().claim_shares(now, limit)
  @impl true
  def finish_share(barcode, changes, now), do: adapter().finish_share(barcode, changes, now)

  @impl true
  def list_custom_foods(user_id), do: adapter().list_custom_foods(user_id)
  @impl true
  def get_custom_food(id, user_id), do: adapter().get_custom_food(id, user_id)
  @impl true
  def custom_food_by_barcode(user_id, barcode),
    do: adapter().custom_food_by_barcode(user_id, barcode)

  @impl true
  def insert_custom_food(attrs), do: adapter().insert_custom_food(attrs)
  @impl true
  def update_custom_food(food, attrs), do: adapter().update_custom_food(food, attrs)
  @impl true
  def delete_custom_food(food), do: adapter().delete_custom_food(food)

  defp adapter, do: Application.fetch_env!(:palee, :food_store)
end
