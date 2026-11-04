defmodule Palee.Nutrition.Ports.FoodDatabase do
  @moduledoc """
  A public food database looked up by barcode (ADR-376, ADR-421). Adapters:

    * `OpenFoodFactsClient` (ODbL 1.0, no key; a descriptive User-Agent);
    * `UsdaFoodDataCentralClient` (CC0, free api.data.gov key; skipped without);
    * `EctoFoodCatalogue` (product lists Palee is licensed to use, e.g. a
      Greek list; name, brand and size only);
    * `ChainFoodDatabase` (asks the sources above in order, each with its own
      timeout, inside one total budget);
    * `SandboxFoodDatabase` (fixed products, dev and tests).

  `{:ok, attrs}` are `Nutrition.Domain.FoodProduct` cache attributes plus
  `:source` (and `:attribution` when the source is not a fixed one);
  `{:error, :not_found}` when the database has no such product;
  `{:error, :not_configured}` when the source is switched off (no key);
  anything else is transient and retried by the outbox.
  """

  @callback lookup(barcode :: String.t(), language :: String.t()) ::
              {:ok, map()} | {:error, :not_found} | {:error, :not_configured} | {:error, term()}
end
