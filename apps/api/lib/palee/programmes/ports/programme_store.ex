defmodule Palee.Programmes.Ports.ProgrammeStore do
  @moduledoc """
  Persistence of programmes, their versions, purchases, deliveries and
  reviews (ADR-370/371). Every callback takes the tenant context first
  (the seller's `organization_id`).

  Changes of a purchase's state go through `update_purchase/3`, which
  locks the row (`FOR UPDATE`) and applies the domain's decision to what
  is stored, so a webhook, a poll and a refund never race.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()
  @type decide :: (map() -> {:ok, map()} | {:error, term()})

  @doc "Runs `fun` (`{:ok, value} | {:error, reason}`) in one transaction."
  @callback transaction(context(), (-> {:ok, term()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}

  # Programmes
  @callback create_programme(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_programme(context(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback set_state(context(), map(), map()) :: {:ok, map()} | {:error, term()}
  @doc "ADR-541: sets or clears the cover fields."
  @callback set_cover(context(), map(), map()) :: {:ok, map()} | {:error, term()}
  @doc "ADR-541: whether a programme other than `except_id` shows one of `media_ids`."
  @callback cover_in_use?(context(), [id()], id()) :: boolean()
  @callback get_programme(context(), id()) :: map() | nil
  @callback list_programmes(context(), map()) :: [map()]
  @doc "Inserts the next version and points the programme at it, in one transaction."
  @callback publish_version(context(), id(), map(), map()) ::
              {:ok, %{programme: map(), version: map()}} | {:error, term()}
  @callback get_version(context(), id()) :: map() | nil
  @callback list_versions(context(), id()) :: [map()]

  # Purchases
  @doc "Inserts a purchase, or returns the one with the same idempotency key."
  @callback create_purchase(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_purchase(context(), id()) :: map() | nil
  @callback purchase_by_intent(context(), id()) :: map() | nil
  @callback open_purchase(context(), id(), id()) :: map() | nil
  @callback set_purchase_intent(context(), id(), id()) :: {:ok, map()} | {:error, term()}
  @callback update_purchase(context(), id(), decide()) :: {:ok, map()} | {:error, term()}
  @doc "ADR-540: like `update_purchase/3` for the buyer's moves and skips."
  @callback update_schedule(context(), id(), decide()) :: {:ok, map()} | {:error, term()}
  @callback list_purchases(context(), map()) :: [map()]
  @doc "Active purchases whose last day is before `today`."
  @callback due_completions(context(), Date.t()) :: [map()]
  @callback sales(context(), [id()]) :: %{id() => map()}

  # Deliveries
  @callback record_deliveries(context(), id(), id(), [map()]) :: :ok
  @callback deliveries(context(), id(), Date.t() | nil) :: [map()]
  @callback delete_deliveries(context(), id(), Date.t()) :: non_neg_integer()
  @doc "ADR-540: moves delivery rows (`[{delivery_id, date}]`) of a purchase."
  @callback move_deliveries(context(), id(), [{id(), Date.t()}]) :: :ok

  # Reviews
  @callback save_review(context(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_review(context(), id()) :: map() | nil
  @callback review_for_purchase(context(), id()) :: map() | nil
  @callback list_reviews(context(), id(), map()) :: [map()]
  @callback moderate_review(context(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback review_summaries(context(), [id()]) :: %{id() => map()}
end
