defmodule Palee.Infrastructure.Integrations.EctoIntegrationStore do
  @moduledoc "Ecto adapter of the open platform store (ADR-378..380)."

  @behaviour Palee.Integrations.Ports.IntegrationStore

  import Ecto.Query

  alias Palee.Integrations.{
    ApiKey,
    AudienceConnection,
    AudienceMember,
    IdempotencyRecord,
    MarketingConsent,
    WebhookDelivery,
    WebhookDeliveryAttempt,
    WebhookEndpoint
  }

  alias Palee.Integrations.Domain.DeliveryPolicy
  alias Palee.Repo

  @max_page 200
  @touch_seconds 60
  @connection_lease_seconds 600

  @impl true
  def transaction(_context, fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── API keys ────────────────────────────────────────────────────────────

  @impl true
  def lookup_api_key(prefix) when is_binary(prefix) do
    case Repo.query("SELECT id, organization_id FROM palee_api_key_lookup($1)", [prefix]) do
      {:ok, %{rows: [[id, organization_id]]}} ->
        %{id: Ecto.UUID.load!(id), organization_id: Ecto.UUID.load!(organization_id)}

      _none ->
        nil
    end
  end

  @impl true
  def insert_api_key(_context, attrs) do
    %ApiKey{} |> ApiKey.changeset(attrs) |> Repo.insert() |> plain_result()
  end

  @impl true
  def list_api_keys(%{organization_id: organization_id}) do
    ApiKey
    |> where([k], k.organization_id == ^organization_id)
    |> order_by([k], asc_nulls_first: k.revoked_at, desc: k.inserted_at)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def get_api_key(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %ApiKey{} = key <-
           Repo.one(
             from k in ApiKey, where: k.organization_id == ^organization_id and k.id == ^id
           ) do
      plain(key)
    else
      _missing -> nil
    end
  end

  @impl true
  def update_api_key(%{organization_id: organization_id}, id, changes) do
    case Repo.one(from k in ApiKey, where: k.organization_id == ^organization_id and k.id == ^id) do
      nil -> {:error, :not_found}
      key -> key |> ApiKey.changeset(changes) |> Repo.update() |> plain_result()
    end
  end

  @impl true
  def touch_api_key(%{organization_id: organization_id}, id, %DateTime{} = now) do
    stale = DateTime.add(now, -@touch_seconds, :second)

    ApiKey
    |> where([k], k.organization_id == ^organization_id and k.id == ^id)
    |> where([k], is_nil(k.last_used_at) or k.last_used_at < ^stale)
    |> Repo.update_all(set: [last_used_at: now])

    :ok
  end

  # ── Idempotency ─────────────────────────────────────────────────────────

  @impl true
  def start_idempotent(%{organization_id: organization_id} = context, attrs) do
    changeset = IdempotencyRecord.changeset(%IdempotencyRecord{}, attrs)

    if changeset.valid? do
      now = DateTime.utc_now()

      row =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Map.take([:principal, :key, :operation, :request_hash, :state, :expires_at])
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          inserted_at: now,
          updated_at: now
        })

      # A conflict inserts nothing (and returns no row): the key is known.
      case Repo.insert_all(IdempotencyRecord, [row], on_conflict: :nothing, returning: [:id]) do
        {1, [%{id: id}]} -> {:ok, %{id: id}}
        {0, []} -> existing_idempotent(context, attrs, now)
      end
    else
      {:error, changeset}
    end
  end

  # An expired record (not swept yet) no longer counts: it is replaced.
  defp existing_idempotent(%{organization_id: organization_id} = context, attrs, now) do
    existing =
      Repo.one(
        from r in IdempotencyRecord,
          where:
            r.organization_id == ^organization_id and r.principal == ^attrs.principal and
              r.key == ^attrs.key
      )

    cond do
      is_nil(existing) ->
        {:error, :idempotency_key_in_use}

      DateTime.compare(existing.expires_at, now) == :lt ->
        Repo.delete(existing)
        start_idempotent(context, attrs)

      true ->
        {:exists, plain(existing)}
    end
  end

  @impl true
  def finish_idempotent(%{organization_id: organization_id}, id, status, body) do
    IdempotencyRecord
    |> where([r], r.organization_id == ^organization_id and r.id == ^id)
    |> Repo.update_all(
      set: [
        state: "completed",
        response_status: status,
        response_body: body,
        updated_at: DateTime.utc_now()
      ]
    )

    :ok
  end

  @impl true
  def forget_idempotent(%{organization_id: organization_id}, id) do
    IdempotencyRecord
    |> where([r], r.organization_id == ^organization_id and r.id == ^id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def purge_idempotency(%{organization_id: organization_id}, %DateTime{} = now) do
    {count, _rows} =
      IdempotencyRecord
      |> where([r], r.organization_id == ^organization_id and r.expires_at < ^now)
      |> Repo.delete_all()

    count
  end

  # ── Webhook endpoints ───────────────────────────────────────────────────

  @impl true
  def insert_endpoint(_context, attrs) do
    %WebhookEndpoint{} |> WebhookEndpoint.changeset(attrs) |> Repo.insert() |> plain_result()
  end

  @impl true
  def list_endpoints(%{organization_id: organization_id}, filters) do
    WebhookEndpoint
    |> where([e], e.organization_id == ^organization_id)
    |> maybe_where(:api_key_id, filters[:api_key_id])
    |> maybe_where(:source, filters[:source])
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def get_endpoint(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %WebhookEndpoint{} = endpoint <-
           Repo.one(
             from e in WebhookEndpoint,
               where: e.organization_id == ^organization_id and e.id == ^id
           ) do
      plain(endpoint)
    else
      _missing -> nil
    end
  end

  @impl true
  def update_endpoint(%{organization_id: organization_id}, id, changes) do
    query =
      from e in WebhookEndpoint, where: e.organization_id == ^organization_id and e.id == ^id

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      endpoint ->
        endpoint |> WebhookEndpoint.changeset(changes) |> Repo.update() |> plain_result()
    end
  end

  @impl true
  def delete_endpoint(%{organization_id: organization_id}, id) do
    WebhookEndpoint
    |> where([e], e.organization_id == ^organization_id and e.id == ^id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def subscribed_endpoints(%{organization_id: organization_id}, type) do
    WebhookEndpoint
    |> where([e], e.organization_id == ^organization_id and e.status == "active")
    |> where([e], ^type in e.events)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  # ── Deliveries ──────────────────────────────────────────────────────────

  @impl true
  def insert_deliveries(_context, rows) do
    Repo.transaction(fn ->
      Enum.map(rows, fn attrs ->
        %WebhookDelivery{} |> WebhookDelivery.changeset(attrs) |> Repo.insert!() |> plain()
      end)
    end)
  end

  @impl true
  def claim_deliveries(%{organization_id: organization_id}, which, %DateTime{} = now, limit) do
    stale = DateTime.add(now, -DeliveryPolicy.lease_seconds(), :second)

    query =
      WebhookDelivery
      |> where([d], d.organization_id == ^organization_id and d.status == "pending")
      |> where([d], is_nil(d.claimed_at) or d.claimed_at < ^stale)

    query =
      case which do
        :due -> where(query, [d], d.next_attempt_at <= ^now)
        id -> where(query, [d], d.id == ^id)
      end

    ids =
      query
      |> order_by([d], asc: d.next_attempt_at, asc: d.inserted_at)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([d], d.id)

    {_count, rows} =
      WebhookDelivery
      |> where([d], d.id in subquery(ids))
      |> select([d], d)
      |> Repo.update_all(set: [claimed_at: now, updated_at: now])

    rows |> Enum.sort_by(&{&1.next_attempt_at, &1.inserted_at}) |> Enum.map(&plain/1)
  end

  @impl true
  def update_delivery(%{organization_id: organization_id}, id, changes) do
    query =
      from d in WebhookDelivery, where: d.organization_id == ^organization_id and d.id == ^id

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      delivery ->
        delivery |> WebhookDelivery.changeset(changes) |> Repo.update() |> plain_result()
    end
  end

  @impl true
  def record_attempt(_context, attrs) do
    %WebhookDeliveryAttempt{} |> WebhookDeliveryAttempt.changeset(attrs) |> Repo.insert!()
    :ok
  end

  @impl true
  def list_deliveries(%{organization_id: organization_id}, filters) do
    limit = min(filters[:limit] || 50, @max_page)
    offset = filters[:offset] || 0

    query =
      WebhookDelivery
      |> where([d], d.organization_id == ^organization_id)
      |> maybe_where(:endpoint_id, filters[:endpoint_id])
      |> maybe_where(:status, filters[:status])

    total = Repo.aggregate(query, :count)

    deliveries =
      query
      |> order_by([d], desc: d.inserted_at)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(&plain/1)

    %{deliveries: deliveries, total: total}
  end

  @impl true
  def get_delivery(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %WebhookDelivery{} = delivery <-
           Repo.one(
             from d in WebhookDelivery,
               where: d.organization_id == ^organization_id and d.id == ^id
           ) do
      attempts =
        WebhookDeliveryAttempt
        |> where([a], a.organization_id == ^organization_id and a.delivery_id == ^id)
        |> order_by([a], asc: a.attempt, asc: a.started_at)
        |> Repo.all()
        |> Enum.map(&plain/1)

      delivery |> plain() |> Map.put(:attempts_log, attempts)
    else
      _missing -> nil
    end
  end

  @impl true
  def due_organizations(%DateTime{} = now) do
    case Repo.query("SELECT palee_webhook_due_organizations($1)", [now]) do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
      {:error, _reason} -> []
    end
  end

  # ── Audience ────────────────────────────────────────────────────────────

  @impl true
  def get_connection(%{organization_id: organization_id}) do
    AudienceConnection
    |> where([c], c.organization_id == ^organization_id)
    |> Repo.one()
    |> connection_map()
  end

  @impl true
  def save_connection(%{organization_id: organization_id}, attrs) do
    attrs =
      case attrs do
        %{credentials: map} when is_map(map) -> %{attrs | credentials: Jason.encode!(map)}
        _other -> attrs
      end

    case Repo.one(from c in AudienceConnection, where: c.organization_id == ^organization_id) do
      nil -> %AudienceConnection{organization_id: organization_id}
      connection -> connection
    end
    |> AudienceConnection.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, connection} -> {:ok, connection_map(connection)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def delete_connection(%{organization_id: organization_id}) do
    AudienceConnection |> where([c], c.organization_id == ^organization_id) |> Repo.delete_all()
    :ok
  end

  @impl true
  def claim_connection(%{organization_id: organization_id}, %DateTime{} = now) do
    stale = DateTime.add(now, -@connection_lease_seconds, :second)

    {count, rows} =
      AudienceConnection
      |> where([c], c.organization_id == ^organization_id and c.status == "active")
      |> where([c], is_nil(c.claimed_at) or c.claimed_at < ^stale)
      |> select([c], c)
      |> Repo.update_all(set: [claimed_at: now])

    if count == 1, do: rows |> hd() |> connection_map()
  end

  @impl true
  def get_consent(%{organization_id: organization_id}, user_id) do
    MarketingConsent
    |> where([c], c.organization_id == ^organization_id and c.user_id == ^user_id)
    |> where([c], c.channel == "email")
    |> Repo.one()
    |> plain()
  end

  @impl true
  def put_consent(%{organization_id: organization_id}, user_id, attrs) do
    query =
      from c in MarketingConsent,
        where:
          c.organization_id == ^organization_id and c.user_id == ^user_id and
            c.channel == "email"

    (Repo.one(query) || %MarketingConsent{organization_id: organization_id})
    |> MarketingConsent.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert_or_update()
    |> plain_result()
  end

  @impl true
  def consented_user_ids(%{organization_id: organization_id}) do
    MarketingConsent
    |> where([c], c.organization_id == ^organization_id and c.channel == "email")
    |> where([c], not is_nil(c.granted_at) and is_nil(c.withdrawn_at))
    |> select([c], c.user_id)
    |> Repo.all()
  end

  @impl true
  def list_audience_members(%{organization_id: organization_id}, connection_id) do
    AudienceMember
    |> where([m], m.organization_id == ^organization_id and m.connection_id == ^connection_id)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def upsert_audience_member(%{organization_id: organization_id}, attrs) do
    now = DateTime.utc_now()

    %AudienceMember{organization_id: organization_id}
    |> AudienceMember.changeset(attrs)
    |> Repo.insert!(
      on_conflict: [
        set: [
          email_hash: attrs.email_hash,
          status: attrs.status,
          synced_at: attrs.synced_at,
          last_error: attrs[:last_error],
          updated_at: now
        ]
      ],
      conflict_target: [:connection_id, :user_id]
    )

    :ok
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp maybe_where(query, _field, nil), do: query
  defp maybe_where(query, field, value), do: where(query, [row], field(row, ^field) == ^value)

  defp connection_map(nil), do: nil

  defp connection_map(%AudienceConnection{} = connection) do
    credentials =
      case connection.credentials && Jason.decode(connection.credentials) do
        {:ok, map} when is_map(map) -> map
        _missing -> %{}
      end

    connection |> plain() |> Map.put(:credentials, credentials)
  end

  defp plain_result({:ok, struct}), do: {:ok, plain(struct)}
  defp plain_result({:error, _reason} = error), do: error

  defp plain(nil), do: nil
  defp plain(%_{} = struct), do: struct |> Map.from_struct() |> Map.delete(:__meta__)
end
