defmodule Palee.Nutrition.Ports.FoodDatabase do
  @moduledoc """
  A public food database looked up by barcode (ADR-376). Adapters:
  `OpenFoodFactsClient` (ODbL 1.0, no key; a descriptive User-Agent is
  required) and `SandboxFoodDatabase` (fixed products, dev and tests).

  `{:ok, attrs}` are `Nutrition.Domain.FoodProduct` cache attributes;
  `{:error, :not_found}` when the database has no such product; anything
  else is transient and retried by the outbox.
  """

  @callback lookup(barcode :: String.t(), language :: String.t()) ::
              {:ok, map()} | {:error, :not_found} | {:error, term()}
end
