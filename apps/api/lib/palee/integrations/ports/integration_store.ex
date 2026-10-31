defmodule Palee.Integrations.Ports.IntegrationStore do
  @moduledoc """
  Persistence of the open platform (ADR-378..380): API keys, idempotency
  records, webhook endpoints and their outbox, the audience connection and
  marketing consents. Every callback but the two tenant look-ups takes the
  tenant context first. Claims lease rows (`claimed_at`, `FOR UPDATE SKIP
  LOCKED`) so two workers never send the same delivery at once.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @callback transaction(context(), (-> {:ok, term()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}

  # API keys
  @doc "The key's id and box from its public prefix, before any tenant session."
  @callback lookup_api_key(prefix :: String.t()) :: %{id: id(), organization_id: id()} | nil
  @callback insert_api_key(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_api_keys(context()) :: [map()]
  @callback get_api_key(context(), id()) :: map() | nil
  @callback update_api_key(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @doc "Marks the key used, at most once a minute."
  @callback touch_api_key(context(), id(), DateTime.t()) :: :ok

  # Idempotency
  @doc "`{:ok, record}` for a new key, `{:exists, record}` for one already stored."
  @callback start_idempotent(context(), map()) ::
              {:ok, map()} | {:exists, map()} | {:error, term()}
  @callback finish_idempotent(context(), id(), integer(), map()) :: :ok
  @callback forget_idempotent(context(), id()) :: :ok
  @callback purge_idempotency(context(), DateTime.t()) :: non_neg_integer()

  # Webhook endpoints
  @callback insert_endpoint(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_endpoints(context(), map()) :: [map()]
  @callback get_endpoint(context(), id()) :: map() | nil
  @callback update_endpoint(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_endpoint(context(), id()) :: :ok
  @doc "Active endpoints subscribed to `type`."
  @callback subscribed_endpoints(context(), String.t()) :: [map()]

  # Deliveries
  @callback insert_deliveries(context(), [map()]) :: {:ok, [map()]}
  @doc "Leases pending deliveries that are due (or the one with `id`)."
  @callback claim_deliveries(context(), :due | id(), DateTime.t(), pos_integer()) :: [map()]
  @callback update_delivery(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback record_attempt(context(), map()) :: :ok
  @callback list_deliveries(context(), map()) :: %{deliveries: [map()], total: non_neg_integer()}
  @doc "A delivery with its `attempts_log`, or nil."
  @callback get_delivery(context(), id()) :: map() | nil
  @doc "Boxes with deliveries due (the sweep), before any tenant session."
  @callback due_organizations(DateTime.t()) :: [id()]

  # Audience
  @doc "The connection with decoded credentials, or nil."
  @callback get_connection(context()) :: map() | nil
  @callback save_connection(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_connection(context()) :: :ok
  @doc "Leases the connection for one sync run, or nil when another holds it."
  @callback claim_connection(context(), DateTime.t()) :: map() | nil
  @callback get_consent(context(), user_id :: id()) :: map() | nil
  @callback put_consent(context(), user_id :: id(), map()) :: {:ok, map()} | {:error, term()}
  @doc "The members whose marketing-email consent stands now."
  @callback consented_user_ids(context()) :: [id()]
  @callback list_audience_members(context(), connection_id :: id()) :: [map()]
  @callback upsert_audience_member(context(), map()) :: :ok
end
