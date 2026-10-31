defmodule Palee.Integrations do
  @moduledoc """
  The open platform (ADR-378..380, CP-F5): per-box API keys with scopes and
  rotation, ADR-300's idempotency records, signed webhooks with retries, a
  delivery log and replay, and the Mailchimp/Brevo audience connection with
  members' marketing-email consent.

  Secrets (API keys, webhook secrets, provider keys) are shown once, when
  made, and never again: keys are stored as hashes, the rest encrypted.
  Webhook calls never run inside a database transaction; a delivery is
  leased (`claimed_at`) while one worker sends it.
  """

  alias Palee.Integrations.IntegrationStore

  alias Palee.Integrations.Domain.{
    ApiKeyToken,
    DeliveryPolicy,
    EndpointUrl,
    Idempotency,
    PublicEvents,
    Scopes,
    WebhookSignature
  }

  @rotation_grace_hours 24
  @max_keys 25
  @max_endpoints 20
  @audience_providers ~w(sandbox mailchimp brevo)
  @consent_text_version "2026-11-01"

  def rotation_grace_hours, do: @rotation_grace_hours
  def scope_catalog, do: Scopes.catalog()
  def event_catalog, do: PublicEvents.catalog()
  def audience_providers, do: @audience_providers
  def consent_text_version, do: @consent_text_version

  defp transport, do: Application.fetch_env!(:palee, :webhook_transport)

  @doc false
  def audience_provider(provider) do
    :palee |> Application.get_env(:audience_providers, %{}) |> Map.fetch!(provider)
  end

  defp sandbox?, do: Application.get_env(:palee, :open_platform_sandbox, false) == true

  defp key_env, do: Application.get_env(:palee, :api_key_env, "live")

  defp url_options do
    config = Application.get_env(:palee, :webhook_urls, [])

    [
      allow_http: Keyword.get(config, :allow_http, false),
      allow_private: Keyword.get(config, :allow_private, false)
    ]
  end

  # ── API keys ────────────────────────────────────────────────────────────

  @doc "The box's keys, newest first, without hashes."
  def list_api_keys(context), do: context |> IntegrationStore.list_api_keys() |> Enum.map(&key_view/1)

  @doc """
  A new key acting for `actor_id`: `{:ok, %{key, token}}`. The token is in
  this answer only.
  """
  def create_api_key(context, params, actor_id, %DateTime{} = now) do
    with {:ok, name} <- name(params[:name]),
         {:ok, scopes} <- Scopes.normalize(params[:scopes]),
         {:ok, expires_at} <- expiry(params[:expires_at], now),
         :ok <- under_limit(context) do
      token = ApiKeyToken.new(key_env(), random(ApiKeyToken.random_bytes_needed()))

      attrs = %{
        name: name,
        prefix: token.prefix,
        secret_hash: token.hash,
        scopes: scopes,
        created_by_id: actor_id,
        expires_at: expires_at
      }

      with {:ok, key} <- IntegrationStore.insert_api_key(context, attrs),
           do: {:ok, %{key: key_view(key), token: token.token}}
    end
  end

  @doc """
  A new secret for the key. The old one keeps working for
  #{@rotation_grace_hours} hours so integrations can switch without a gap.
  """
  def rotate_api_key(context, id, %DateTime{} = now) do
    with %{revoked_at: nil} = key <- IntegrationStore.get_api_key(context, id) || :not_found do
      token =
        key_env()
        |> ApiKeyToken.new(random(ApiKeyToken.random_bytes_needed()))
        |> rebuild(key.prefix)

      changes = %{
        secret_hash: token.hash,
        previous_secret_hash: key.secret_hash,
        previous_expires_at: DateTime.add(now, @rotation_grace_hours * 3600, :second),
        rotated_at: now
      }

      with {:ok, key} <- IntegrationStore.update_api_key(context, id, changes),
           do: {:ok, %{key: key_view(key), token: token.token}}
    else
      :not_found -> {:error, :not_found}
      %{} -> {:error, :api_key_revoked}
    end
  end

  # A rotated key keeps its prefix (the box and its lists know it by it).
  defp rebuild(%{token: token}, prefix) do
    [_palee, env, _new_prefix, secret] = String.split(token, "_")
    full = "palee_#{env}_#{prefix}_#{secret}"
    %{token: full, prefix: prefix, hash: ApiKeyToken.hash(full)}
  end

  @doc "Stops the key at once; its webhook subscriptions go with it."
  def revoke_api_key(context, id, actor_id, %DateTime{} = now) do
    case IntegrationStore.get_api_key(context, id) do
      nil ->
        {:error, :not_found}

      %{revoked_at: %DateTime{}} = key ->
        {:ok, key_view(key)}

      _key ->
        with {:ok, key} <-
               IntegrationStore.update_api_key(context, id, %{
                 revoked_at: now,
                 revoked_by_id: actor_id,
                 previous_secret_hash: nil,
                 previous_expires_at: nil
               }) do
          context
          |> IntegrationStore.list_endpoints(%{api_key_id: id})
          |> Enum.each(&IntegrationStore.delete_endpoint(context, &1.id))

          {:ok, key_view(key)}
        end
    end
  end

  @doc """
  The key behind a bearer token: `{:ok, %{organization_id, key}}` or
  `{:error, :invalid_api_key}`. Revoked, expired and unknown keys look the
  same to the caller.
  """
  def authenticate(token, %DateTime{} = now) when is_binary(token) do
    with {:ok, prefix} <- ApiKeyToken.parse(token),
         %{organization_id: organization_id, id: id} <- IntegrationStore.lookup_api_key(prefix),
         context = %{organization_id: organization_id},
         %{revoked_at: nil} = key <- IntegrationStore.get_api_key(context, id),
         true <- not expired?(key.expires_at, now),
         true <- token_matches?(token, key, now) do
      IntegrationStore.touch_api_key(context, id, now)
      {:ok, %{organization_id: organization_id, key: key_view(key)}}
    else
      _invalid -> {:error, :invalid_api_key}
    end
  end

  def authenticate(_token, _now), do: {:error, :invalid_api_key}

  defp token_matches?(token, key, now) do
    ApiKeyToken.matches?(token, key.secret_hash) or
      (not expired?(key.previous_expires_at, now) and
         ApiKeyToken.matches?(token, key.previous_secret_hash))
  end

  defp expired?(nil, _now), do: false
  defp expired?(%DateTime{} = at, now), do: DateTime.compare(at, now) != :gt

  defp key_view(key) do
    %{
      id: key.id,
      name: key.name,
      prefix: key.prefix,
      masked: ApiKeyToken.masked(key_env(), key.prefix),
      scopes: key.scopes,
      created_by_id: key.created_by_id,
      created_at: key.inserted_at,
      last_used_at: key.last_used_at,
      expires_at: key.expires_at,
      rotated_at: key.rotated_at,
      previous_secret_expires_at: key.previous_expires_at,
      revoked_at: key.revoked_at,
      status: key_status(key)
    }
  end

  defp key_status(%{revoked_at: %DateTime{}}), do: "revoked"
  defp key_status(_key), do: "active"

  defp under_limit(context) do
    active = context |> IntegrationStore.list_api_keys() |> Enum.count(&is_nil(&1.revoked_at))
    if active < @max_keys, do: :ok, else: {:error, :too_many_api_keys}
  end

  defp name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> {:error, :invalid_api_key_name}
      trimmed when byte_size(trimmed) <= 80 -> {:ok, trimmed}
      _long -> {:error, :invalid_api_key_name}
    end
  end

  defp name(_name), do: {:error, :invalid_api_key_name}

  defp expiry(nil, _now), do: {:ok, nil}

  defp expiry(%DateTime{} = at, now) do
    if DateTime.compare(at, now) == :gt, do: {:ok, at}, else: {:error, :invalid_api_key_expiry}
  end

  defp expiry(value, now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> expiry(at, now)
      _invalid -> {:error, :invalid_api_key_expiry}
    end
  end

  defp expiry(_value, _now), do: {:error, :invalid_api_key_expiry}

  # ── Idempotency (ADR-300) ───────────────────────────────────────────────

  @doc """
  Starts a command under `key`: `{:ok, record_id}` to run it, `{:replay,
  status, body}` for a key already answered, or an error.
  """
  def begin_idempotent(context, principal, key, operation, input, %DateTime{} = now) do
    with {:ok, key} <- Idempotency.validate_key(key) do
      hash = Idempotency.fingerprint(operation, input)

      attrs = %{
        principal: principal,
        key: key,
        operation: operation,
        request_hash: hash,
        expires_at: Idempotency.expires_at(now)
      }

      case IntegrationStore.start_idempotent(context, attrs) do
        {:ok, record} -> {:ok, record.id}
        {:exists, record} -> Idempotency.decide(record, hash)
        {:error, _reason} = error -> error
      end
    end
  end

  @doc "Keeps the first answer (any answer the client should see again)."
  def complete_idempotent(context, record_id, status, body),
    do: IntegrationStore.finish_idempotent(context, record_id, status, body)

  @doc "Frees the key after an unexpected failure, so the client may try again."
  def abandon_idempotent(context, record_id), do: IntegrationStore.forget_idempotent(context, record_id)

  @doc "Removes expired records (the sweep)."
  def purge_idempotency(context, now), do: IntegrationStore.purge_idempotency(context, now)

  # ── Webhook endpoints ───────────────────────────────────────────────────

  @doc """
  Endpoints of the box (`source`: `staff` ones from Settings, `api` ones
  that Zapier/Make made), without secrets.
  """
  def list_endpoints(context, filters \\ %{}),
    do: context |> IntegrationStore.list_endpoints(filters) |> Enum.map(&endpoint_view/1)

  def get_endpoint(context, id) do
    case IntegrationStore.get_endpoint(context, id) do
      nil -> {:error, :not_found}
      endpoint -> {:ok, endpoint_view(endpoint)}
    end
  end

  @doc """
  A new endpoint: `{:ok, %{endpoint, secret}}`; the signing secret is in
  this answer only. `opts`: `source` (`staff` | `api`), `api_key_id`.
  """
  def create_endpoint(context, params, actor_id, opts \\ []) do
    source = Keyword.get(opts, :source, "staff")

    with {:ok, url} <- EndpointUrl.validate(params[:url], url_options()),
         {:ok, events} <- PublicEvents.normalize(params[:events]),
         :ok <- endpoint_scopes(events, Keyword.get(opts, :scopes)),
         {:ok, description} <- description(params[:description]),
         :ok <- endpoint_limit(context) do
      secret = new_secret()

      attrs = %{
        url: url,
        events: events,
        description: description,
        secret: secret,
        status: "active",
        source: source,
        api_key_id: Keyword.get(opts, :api_key_id),
        created_by_id: actor_id
      }

      with {:ok, endpoint} <- IntegrationStore.insert_endpoint(context, attrs),
           do: {:ok, %{endpoint: endpoint_view(endpoint), secret: secret}}
    end
  end

  @doc "Changes the URL, events, description or status (`active` turns a disabled one back on)."
  def update_endpoint(context, id, params) do
    with %{} = endpoint <- IntegrationStore.get_endpoint(context, id) || {:error, :not_found},
         {:ok, changes} <- endpoint_changes(endpoint, params) do
      with {:ok, endpoint} <- IntegrationStore.update_endpoint(context, id, changes),
           do: {:ok, endpoint_view(endpoint)}
    end
  end

  defp endpoint_changes(_endpoint, params) do
    Enum.reduce_while([:url, :events, :description, :status], {:ok, %{}}, fn field, {:ok, acc} ->
      case endpoint_change(field, Map.fetch(params, field)) do
        :skip -> {:cont, {:ok, acc}}
        {:ok, changes} -> {:cont, {:ok, Map.merge(acc, changes)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp endpoint_change(_field, :error), do: :skip

  defp endpoint_change(:url, {:ok, url}) do
    with {:ok, url} <- EndpointUrl.validate(url, url_options()), do: {:ok, %{url: url}}
  end

  defp endpoint_change(:events, {:ok, events}) do
    with {:ok, events} <- PublicEvents.normalize(events), do: {:ok, %{events: events}}
  end

  defp endpoint_change(:description, {:ok, value}) do
    with {:ok, description} <- description(value), do: {:ok, %{description: description}}
  end

  defp endpoint_change(:status, {:ok, "active"}),
    do: {:ok, %{status: "active", disabled_reason: nil, consecutive_failures: 0}}

  defp endpoint_change(:status, {:ok, "disabled"}),
    do: {:ok, %{status: "disabled", disabled_reason: "by_staff"}}

  defp endpoint_change(:status, {:ok, _other}), do: {:error, :invalid_webhook_status}

  def delete_endpoint(context, id) do
    case IntegrationStore.get_endpoint(context, id) do
      nil -> {:error, :not_found}
      _endpoint -> IntegrationStore.delete_endpoint(context, id)
    end
  end

  @doc "A REST-hook unsubscribe: only the key that made the subscription may remove it."
  def delete_key_endpoint(context, api_key_id, id) do
    case IntegrationStore.get_endpoint(context, id) do
      %{api_key_id: ^api_key_id} -> IntegrationStore.delete_endpoint(context, id)
      _other -> {:error, :not_found}
    end
  end

  @doc """
  A new signing secret; the previous one also signs for
  #{@rotation_grace_hours} hours. `{:ok, %{endpoint, secret}}`.
  """
  def rotate_endpoint_secret(context, id, %DateTime{} = now) do
    with %{} = endpoint <- IntegrationStore.get_endpoint(context, id) || {:error, :not_found} do
      secret = new_secret()

      changes = %{
        secret: secret,
        previous_secret: endpoint.secret,
        previous_secret_expires_at: DateTime.add(now, @rotation_grace_hours * 3600, :second)
      }

      with {:ok, endpoint} <- IntegrationStore.update_endpoint(context, id, changes),
           do: {:ok, %{endpoint: endpoint_view(endpoint), secret: secret}}
    end
  end

  defp endpoint_scopes(_events, nil), do: :ok

  defp endpoint_scopes(events, scopes) do
    if Enum.all?(events, &Scopes.allows?(scopes, PublicEvents.scope_for(&1))),
      do: :ok,
      else: {:error, :insufficient_scope}
  end

  defp endpoint_limit(context) do
    if length(IntegrationStore.list_endpoints(context, %{})) < @max_endpoints,
      do: :ok,
      else: {:error, :too_many_webhooks}
  end

  defp description(nil), do: {:ok, nil}

  defp description(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> {:ok, nil}
      String.length(value) <= 200 -> {:ok, value}
      true -> {:error, :invalid_webhook_description}
    end
  end

  defp description(_value), do: {:error, :invalid_webhook_description}

  defp endpoint_view(endpoint) do
    %{
      id: endpoint.id,
      url: endpoint.url,
      description: endpoint.description,
      events: endpoint.events,
      status: endpoint.status,
      source: endpoint.source,
      api_key_id: endpoint.api_key_id,
      disabled_reason: endpoint.disabled_reason,
      consecutive_failures: endpoint.consecutive_failures,
      last_success_at: endpoint.last_success_at,
      last_failure_at: endpoint.last_failure_at,
      secret_rotating_until: endpoint.previous_secret_expires_at,
      created_at: endpoint.inserted_at
    }
  end

  defp new_secret, do: "whsec_" <> Base.url_encode64(random(32), padding: false)

  # ── Events into the outbox ──────────────────────────────────────────────

  @doc """
  Puts a public event in the outbox of every endpoint subscribed to it:
  `{:ok, count}`. The same `event_id` goes to every endpoint, so receivers
  can drop duplicates.
  """
  def enqueue_event(context, type, data, event_id, %DateTime{} = at, %DateTime{} = now) do
    case IntegrationStore.subscribed_endpoints(context, type) do
      [] ->
        {:ok, 0}

      endpoints ->
        payload = PublicEvents.envelope(event_id, type, data, context.organization_id, at)

        rows =
          Enum.map(endpoints, fn endpoint ->
            %{
              endpoint_id: endpoint.id,
              event_id: event_id,
              event_type: type,
              payload: payload,
              status: "pending",
              next_attempt_at: now
            }
          end)

        with {:ok, deliveries} <- IntegrationStore.insert_deliveries(context, rows),
             do: {:ok, length(deliveries)}
    end
  end

  @doc "A `ping` to one endpoint (Settings › «Δοκιμή»): `{:ok, delivery}`."
  def enqueue_ping(context, endpoint_id, event_id, %DateTime{} = now) do
    with %{} = endpoint <- IntegrationStore.get_endpoint(context, endpoint_id) || {:error, :not_found} do
      payload =
        PublicEvents.envelope(
          event_id,
          PublicEvents.ping_type(),
          %{endpoint_id: endpoint.id},
          context.organization_id,
          now
        )

      insert_one(context, %{
        endpoint_id: endpoint.id,
        event_id: event_id,
        event_type: PublicEvents.ping_type(),
        payload: payload,
        status: "pending",
        next_attempt_at: now
      })
    end
  end

  @doc """
  Sends a delivered or failed event again, as a new delivery with the same
  event id (`replay_of_id` names the original): `{:ok, delivery}`.
  """
  def replay(context, delivery_id, %DateTime{} = now) do
    with %{} = original <- IntegrationStore.get_delivery(context, delivery_id) || {:error, :not_found},
         %{status: "active"} <-
           IntegrationStore.get_endpoint(context, original.endpoint_id) ||
             {:error, :webhook_disabled},
         true <- original.status != "pending" || {:error, :delivery_pending} do
      insert_one(context, %{
        endpoint_id: original.endpoint_id,
        event_id: original.event_id,
        event_type: original.event_type,
        payload: original.payload,
        status: "pending",
        next_attempt_at: now,
        replay_of_id: original.id
      })
    else
      %{status: _disabled} -> {:error, :webhook_disabled}
      {:error, _reason} = error -> error
    end
  end

  defp insert_one(context, row) do
    with {:ok, [delivery]} <- IntegrationStore.insert_deliveries(context, [row]),
         do: {:ok, delivery_view(delivery)}
  end

  def list_deliveries(context, filters) do
    context
    |> IntegrationStore.list_deliveries(filters)
    |> Map.update!(:deliveries, fn rows -> Enum.map(rows, &delivery_view/1) end)
  end

  def get_delivery(context, id) do
    case IntegrationStore.get_delivery(context, id) do
      nil ->
        {:error, :not_found}

      delivery ->
        {:ok,
         delivery
         |> delivery_view()
         |> Map.put(:payload, delivery.payload)
         |> Map.put(:attempts_log, Enum.map(delivery.attempts_log, &attempt_view/1))}
    end
  end

  defp delivery_view(delivery) do
    %{
      id: delivery.id,
      endpoint_id: delivery.endpoint_id,
      event_id: delivery.event_id,
      event_type: delivery.event_type,
      status: delivery.status,
      attempts: delivery.attempts,
      next_attempt_at: delivery.next_attempt_at,
      last_status_code: delivery.last_status_code,
      last_error: delivery.last_error,
      delivered_at: delivery.delivered_at,
      replay_of_id: delivery.replay_of_id,
      created_at: delivery.inserted_at
    }
  end

  defp attempt_view(attempt) do
    Map.take(attempt, [
      :attempt,
      :outcome,
      :status_code,
      :error,
      :response_excerpt,
      :duration_ms,
      :started_at
    ])
  end

  # ── Sending ─────────────────────────────────────────────────────────────

  @doc """
  Sends what is due (or the one delivery `which`): `{:ok, %{sent,
  delivered, failed}}`. Each delivery is leased first, so overlapping runs
  never send twice.
  """
  def deliver(context, which, %DateTime{} = now) do
    counts =
      context
      |> IntegrationStore.claim_deliveries(which, now, DeliveryPolicy.batch())
      |> Enum.reduce(%{sent: 0, delivered: 0, failed: 0}, fn delivery, counts ->
        endpoint = IntegrationStore.get_endpoint(context, delivery.endpoint_id)
        bump(counts, deliver_one(context, delivery, endpoint, now))
      end)

    {:ok, counts}
  end

  defp bump(counts, :delivered), do: %{counts | sent: counts.sent + 1, delivered: counts.delivered + 1}
  defp bump(counts, :failed), do: %{counts | sent: counts.sent + 1, failed: counts.failed + 1}
  defp bump(counts, :retry), do: %{counts | sent: counts.sent + 1}

  # A disabled (or deleted) endpoint's delivery fails without a call.
  defp deliver_one(context, delivery, endpoint, _now)
       when endpoint == nil or endpoint.status != "active" do
    IntegrationStore.update_delivery(context, delivery.id, %{
      status: "failed",
      next_attempt_at: nil,
      claimed_at: nil,
      last_error: "endpoint_disabled"
    })

    :failed
  end

  defp deliver_one(context, delivery, endpoint, now) do
    body = Jason.encode!(delivery.payload)
    attempt = delivery.attempts + 1

    headers = [
      {"content-type", "application/json"},
      {"user-agent", "Palee-Webhooks/1"},
      {"palee-event-id", delivery.event_id},
      {"palee-event-type", delivery.event_type},
      {"palee-delivery-id", delivery.id},
      {WebhookSignature.header_name(),
       WebhookSignature.header(secrets(endpoint, now), DateTime.to_unix(now), body)}
    ]

    started = System.monotonic_time(:millisecond)
    result = transport().post(endpoint.url, headers, body)
    duration = System.monotonic_time(:millisecond) - started

    outcome =
      DeliveryPolicy.classify(
        case result do
          {:ok, %{status: status}} -> {:ok, status}
          {:error, reason} -> {:error, reason}
        end
      )

    {status_code, excerpt, error} =
      case result do
        {:ok, %{status: status, body_excerpt: excerpt}} -> {status, excerpt, nil}
        {:error, reason} -> {nil, nil, error_text(reason)}
      end

    IntegrationStore.record_attempt(context, %{
      delivery_id: delivery.id,
      attempt: attempt,
      outcome: Atom.to_string(outcome),
      status_code: status_code,
      error: error,
      response_excerpt: excerpt,
      duration_ms: duration,
      started_at: now
    })

    {status, next_at} = DeliveryPolicy.after_attempt(outcome, attempt, now)

    IntegrationStore.update_delivery(context, delivery.id, %{
      status: Atom.to_string(status),
      attempts: attempt,
      next_attempt_at: next_at,
      claimed_at: nil,
      last_status_code: status_code,
      last_error: error,
      delivered_at: if(status == :succeeded, do: now)
    })

    settle_endpoint(context, endpoint, outcome, status, now)

    case status do
      :succeeded -> :delivered
      :failed -> :failed
      :pending -> :retry
    end
  end

  # The endpoint's health changes when a delivery ends, not on every retry.
  defp settle_endpoint(_context, _endpoint, _outcome, :pending, _now), do: :ok

  defp settle_endpoint(context, endpoint, outcome, _final, now) do
    changes =
      case DeliveryPolicy.endpoint_after(outcome, endpoint.consecutive_failures) do
        :healthy ->
          %{consecutive_failures: 0, last_success_at: now}

        :count ->
          %{consecutive_failures: endpoint.consecutive_failures + 1, last_failure_at: now}

        {:disable, reason} ->
          %{
            status: "disabled",
            disabled_reason: reason,
            consecutive_failures: endpoint.consecutive_failures + 1,
            last_failure_at: now
          }
      end

    IntegrationStore.update_endpoint(context, endpoint.id, changes)
    :ok
  end

  defp secrets(endpoint, now) do
    previous =
      if endpoint.previous_secret && not expired?(endpoint.previous_secret_expires_at, now),
        do: [endpoint.previous_secret],
        else: []

    [endpoint.secret | previous]
  end

  defp error_text(reason) when is_binary(reason), do: String.slice(reason, 0, 300)
  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(reason), do: reason |> inspect() |> String.slice(0, 300)

  @doc "Boxes with deliveries due (the minute sweep)."
  def due_organizations(now), do: IntegrationStore.due_organizations(now)

  # ── Audience connection and consent (ADR-380) ───────────────────────────

  @doc "The box's list connection, without its key, or nil."
  def connection(context), do: context |> IntegrationStore.get_connection() |> connection_view()

  @doc "The connection with its key, for the sync (never returned by the API)."
  def connection_for_sync(context), do: IntegrationStore.get_connection(context)

  @doc """
  Saves the connection after the provider accepted the key: `{:ok,
  connection}`. A key left out keeps the saved one for the same provider.
  """
  def save_connection(context, params, actor_id) do
    provider = params[:provider]
    previous = IntegrationStore.get_connection(context)

    with true <- provider in @audience_providers || {:error, :invalid_audience_provider},
         true <- provider != "sandbox" or sandbox?() || {:error, :invalid_audience_provider},
         {:ok, list_id} <- list_id(params[:list_id]),
         {:ok, credentials} <- audience_credentials(provider, params[:api_key], previous),
         candidate = %{list_id: list_id, credentials: credentials},
         :ok <- check_audience(provider, candidate) do
      attrs = %{
        provider: provider,
        list_id: list_id,
        credentials: if(provider == "sandbox", do: nil, else: credentials),
        status: "active",
        last_error: nil,
        updated_by_id: actor_id
      }

      with {:ok, saved} <- IntegrationStore.save_connection(context, attrs),
           do: {:ok, connection_view(saved)}
    end
  end

  defp check_audience(provider, candidate) do
    case audience_provider(provider).check(candidate) do
      :ok -> :ok
      {:error, {:unauthorized, _reason}} -> {:error, :audience_unauthorized}
      {:error, {:rejected, _reason}} -> {:error, :audience_list_not_found}
      {:error, {:transient, _reason}} -> {:error, :audience_unavailable}
    end
  end

  defp list_id(value) when is_binary(value) do
    value = String.trim(value)

    if value =~ ~r/\A[A-Za-z0-9_-]{1,100}\z/,
      do: {:ok, value},
      else: {:error, :invalid_audience_list}
  end

  defp list_id(value) when is_integer(value) and value > 0, do: {:ok, Integer.to_string(value)}
  defp list_id(_value), do: {:error, :invalid_audience_list}

  defp audience_credentials("sandbox", _key, _previous), do: {:ok, %{}}

  defp audience_credentials(provider, key, previous) do
    cond do
      is_binary(key) and String.trim(key) != "" and byte_size(key) <= 200 ->
        {:ok, %{"api_key" => String.trim(key)}}

      match?(%{provider: ^provider, credentials: %{"api_key" => _}}, previous) ->
        {:ok, previous.credentials}

      true ->
        {:error, :audience_key_required}
    end
  end

  def delete_connection(context), do: IntegrationStore.delete_connection(context)

  @doc "Asks for a sync soon (after a consent change or from Settings)."
  def request_sync(context, %DateTime{} = now) do
    case IntegrationStore.get_connection(context) do
      nil -> {:error, :audience_not_connected}
      _connection -> with {:ok, _saved} <- IntegrationStore.save_connection(context, %{sync_requested_at: now}), do: :ok
    end
  end

  @doc "Leases the connection for one sync run: the connection with its key, or nil."
  def claim_sync(context, now), do: IntegrationStore.claim_connection(context, now)

  @doc "Ends a sync run: when it ran, and the first error if any."
  def finish_sync(context, %DateTime{} = now, error) do
    changes =
      case error do
        nil -> %{last_synced_at: now, claimed_at: nil, last_error: nil}
        {:unauthorized, _} -> %{claimed_at: nil, status: "invalid", last_error: "unauthorized"}
        other -> %{claimed_at: nil, last_error: other |> inspect() |> String.slice(0, 300)}
      end

    with {:ok, _saved} <- IntegrationStore.save_connection(context, changes), do: :ok
  end

  def audience_members(context, connection_id),
    do: IntegrationStore.list_audience_members(context, connection_id)

  def record_audience_member(context, attrs), do: IntegrationStore.upsert_audience_member(context, attrs)

  def consented_user_ids(context), do: IntegrationStore.consented_user_ids(context)

  defp connection_view(nil), do: nil

  defp connection_view(connection) do
    %{
      provider: connection.provider,
      list_id: connection.list_id,
      status: connection.status,
      key_saved: connection.credentials not in [nil, %{}],
      last_error: connection.last_error,
      last_synced_at: connection.last_synced_at,
      sync_requested_at: connection.sync_requested_at,
      updated_at: connection.updated_at
    }
  end

  @doc "The member's marketing-email consent in this box: `%{granted, granted_at, withdrawn_at}`."
  def consent(context, user_id) do
    case IntegrationStore.get_consent(context, user_id) do
      nil -> %{granted: false, granted_at: nil, withdrawn_at: nil, text_version: nil}
      row -> consent_view(row)
    end
  end

  @doc """
  The member's own yes or no (never staff on their behalf): `{:ok,
  consent}`. Saying no after yes keeps when they said yes, as proof.
  """
  def set_consent(context, user_id, granted, source, %DateTime{} = now) when is_boolean(granted) do
    previous = IntegrationStore.get_consent(context, user_id)

    attrs =
      if granted,
        do: %{granted_at: now, withdrawn_at: nil},
        else: %{granted_at: previous && previous.granted_at, withdrawn_at: now}

    attrs =
      Map.merge(attrs, %{channel: "email", source: source, text_version: @consent_text_version})

    with {:ok, row} <- IntegrationStore.put_consent(context, user_id, attrs),
         do: {:ok, consent_view(row)}
  end

  def set_consent(_context, _user_id, _granted, _source, _now), do: {:error, :invalid_consent}

  defp consent_view(row) do
    %{
      granted: not is_nil(row.granted_at) and is_nil(row.withdrawn_at),
      granted_at: row.granted_at,
      withdrawn_at: row.withdrawn_at,
      text_version: row.text_version
    }
  end

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: Palee.Integrations.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)

  defp random(bytes), do: :crypto.strong_rand_bytes(bytes)
end
