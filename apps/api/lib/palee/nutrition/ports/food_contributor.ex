defmodule Palee.Nutrition.Ports.FoodContributor do
  @moduledoc """
  Contributes a product members shared to a public food database (ADR-421
  addendum). Adapter: `OpenFoodFactsContributor` (product write API, a
  Palee account from env; skipped when it has none).

  `contribute/1` gets the share (barcode, name, brand, serving size,
  nutrients per 100 g, language and, for the database's own moderation, the
  id the adapter turns into a pseudonym; never sent as such):

    * `:ok` – saved there;
    * `{:error, :exists}` – the database already has the product; nothing
      is overwritten;
    * `{:error, {:rejected, reason}}` – refused for good (not retried);
    * anything else is transient and retried by the outbox.
  """

  @callback configured?() :: boolean()
  @callback contribute(share :: map()) ::
              :ok | {:error, :exists} | {:error, {:rejected, term()}} | {:error, term()}
end
