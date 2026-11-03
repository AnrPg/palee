defmodule Palee.Nutrition.Ports.FoodStore do
  @moduledoc """
  Persistence port of barcode foods (ADR-376). The cache (`food_products`)
  holds no personal data and is read and written outside any person's
  session; custom foods are read and written in the person's own
  RepoContext (row security admits only them).
  """

  alias Palee.Nutrition.{BarcodeMiss, CachedFood, CustomFood}

  @type id :: Ecto.UUID.t()

  @callback get_cached(String.t()) :: CachedFood.t() | nil
  @doc "Inserts a pending row for the barcode (due now), or makes an existing one due now."
  @callback request_lookup(String.t(), DateTime.t()) :: :ok
  @doc "Claims due rows (or this barcode) with FOR UPDATE SKIP LOCKED, counting an attempt."
  @callback claim(:due | String.t(), DateTime.t(), pos_integer()) :: [CachedFood.t()]
  @callback finish(String.t(), map(), DateTime.t()) :: {:ok, CachedFood.t()} | {:error, term()}

  @doc "Counts one scan that found nothing, for the barcode and country (`\"\"` when unknown) (ADR-421)."
  @callback record_miss(String.t(), String.t(), Date.t()) :: :ok
  @doc "The most scanned barcodes nobody had, optionally in one country (ADR-421)."
  @callback list_misses(country :: String.t() | nil, limit :: pos_integer()) :: [BarcodeMiss.t()]

  @callback list_custom_foods(id()) :: [CustomFood.t()]
  @callback get_custom_food(id(), id()) :: CustomFood.t() | nil
  @callback custom_food_by_barcode(id(), String.t()) :: CustomFood.t() | nil
  @callback insert_custom_food(map()) :: {:ok, CustomFood.t()} | {:error, Ecto.Changeset.t()}
  @callback update_custom_food(CustomFood.t(), map()) ::
              {:ok, CustomFood.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_custom_food(CustomFood.t()) :: :ok
end
