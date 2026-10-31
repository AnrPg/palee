defmodule Palee.Nutrition.Ports.FoodStore do
  @moduledoc """
  Persistence port of barcode foods (ADR-376). The cache (`food_products`)
  holds no personal data and is read and written outside any person's
  session; custom foods are read and written in the person's own
  RepoContext (row security admits only them).
  """

  alias Palee.Nutrition.{CachedFood, CustomFood}

  @type id :: Ecto.UUID.t()

  @callback get_cached(String.t()) :: CachedFood.t() | nil
  @doc "Inserts a pending row for the barcode (due now), or makes an existing one due now."
  @callback request_lookup(String.t(), DateTime.t()) :: :ok
  @doc "Claims due rows (or this barcode) with FOR UPDATE SKIP LOCKED, counting an attempt."
  @callback claim(:due | String.t(), DateTime.t(), pos_integer()) :: [CachedFood.t()]
  @callback finish(String.t(), map(), DateTime.t()) :: {:ok, CachedFood.t()} | {:error, term()}

  @callback list_custom_foods(id()) :: [CustomFood.t()]
  @callback get_custom_food(id(), id()) :: CustomFood.t() | nil
  @callback custom_food_by_barcode(id(), String.t()) :: CustomFood.t() | nil
  @callback insert_custom_food(map()) :: {:ok, CustomFood.t()} | {:error, Ecto.Changeset.t()}
  @callback update_custom_food(CustomFood.t(), map()) ::
              {:ok, CustomFood.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_custom_food(CustomFood.t()) :: :ok
end
