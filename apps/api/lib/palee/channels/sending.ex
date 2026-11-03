defmodule Palee.Channels.Sending do
  @moduledoc """
  Sending SMS, Viber and WhatsApp messages through the box's provider
  (ADR-348 §5, ADR-349, ADR-350).

  `send/3` checks everything a message needs before it is queued, in this
  order: the connection, the template, the person's number, a channel the
  person agreed to for this purpose (`ChannelPolicy`), the text, and the
  month's budget (a connection without a cap the box typed sends nothing,
  ADR-390). It then writes one outbox row, idempotent per box by
  `idempotency_key`. Quiet hours do not refuse: a marketing row waits until
  they end; service messages always go at once (ADR-390).

  Workers claim due rows (`deliver/3`), check the consent again (it may
  have been withdrawn while the message waited), call the provider
  outside any transaction and record the attempt. Receipts arrive on the
  box's webhook (`handle_webhook/4`).

  `env` carries what comes from other contexts: `now`, `time_zone` (the
  box's), `box_name`.
  """

  alias Palee.Channels.{ChannelStore, Connections, Contacts, Margins, Unsubscribe}

  alias Palee.Channels.Domain.{
    ChannelPolicy,
    CostPolicy,
    DeliveryPolicy,
    MessageText,
    PhoneNumber,
    QuietHours,
    Templates
  }

  @batch 25

  # ── Preparing ───────────────────────────────────────────────────────────

  @doc """
  What a message would be, without queuing it: `{:ok, plan}` with the
  channel, text, parts, estimated cost, when it would leave and the
  month's budget, or the reason it cannot go (see `send/3`).
  """
  def preview(context, request, env), do: prepare(context, request, env)

  defp prepare(context, request, env) do
    with :ok <- not_demo(env),
         {:ok, connection} <- usable_connection(context),
         :ok <- budget_set(connection),
         {:ok, template} <- template(context, request.template_key),
         {:ok, purpose} <- purpose(template, request[:purpose]),
         {:ok, contact} <- contact(context, request.person),
         whatsapp = whatsapp_template(template, contact.locale),
         {:ok, channel} <-
           ChannelPolicy.choose(%{
             connection: connection,
             contact: contact,
             consents: contact.consents,
             purpose: purpose,
             preferred: request[:channels],
             whatsapp_template?: not is_nil(whatsapp)
           }),
         variables = Map.put_new(request[:variables] || %{}, "box", env.box_name),
         {:ok, {body, locale}} <- body(template, channel, whatsapp, contact.locale),
         {:ok, text} <- Templates.render(body, variables),
         text = opt_out(text, purpose, channel, locale, contact),
         :ok <- length_ok(text) do
      segments = MessageText.segments(channel, text)

      provider_estimate =
        CostPolicy.estimate(
          Application.get_env(:palee, :channel_prices),
          channel,
          purpose,
          PhoneNumber.country(contact.phone_e164),
          segments
        )

      # ADR-369: on Palee's account the box pays the provider's price plus
      # Palee's margin; on its own account, the provider's price only.
      margin = if connection.account_mode == "palee", do: Margins.bps(channel), else: 0
      estimate = CostPolicy.price(provider_estimate, margin)

      {from, to} = CostPolicy.month_range(env.now, env.time_zone)
      spent = ChannelStore.spend(context, from, to).total
      urgent? = request[:urgent] == true and purpose == "service"

      # ADR-390: service messages always go; only marketing waits for quiet hours.
      release_at =
        if QuietHours.applies?(purpose),
          do:
            QuietHours.release_at(
              env.now,
              env.time_zone,
              connection.quiet_start_minute,
              connection.quiet_end_minute
            ),
          else: env.now

      plan = %{
        connection: connection,
        contact: contact,
        channel: channel,
        purpose: purpose,
        template_key: template.key,
        locale: locale,
        body: text,
        template_values: template_values(whatsapp, channel, variables),
        segments: segments,
        encoding: if(channel == "sms", do: MessageText.encoding(text)),
        estimated_cost_cents: estimate,
        provider_cost_cents: provider_estimate,
        margin_bps: margin,
        currency: connection.currency,
        urgent: urgent?,
        release_at: release_at,
        held_for_quiet_hours: DateTime.compare(release_at, env.now) == :gt,
        budget: %{
          spent_cents: spent,
          cap_cents: connection.monthly_budget_cents,
          currency: connection.currency
        },
        replies_possible: replies_possible?(connection, channel)
      }

      with :ok <- CostPolicy.within_budget(spent, estimate, connection.monthly_budget_cents) do
        {:ok, plan}
      end
    end
  end

  # Product owner, 2026-11-02: a box in demo mode (ADR-184) sends no SMS,
  # Viber or WhatsApp; it may still connect and test its provider.
  defp not_demo(%{demo: true}), do: {:error, :channels_demo_mode}
  defp not_demo(_env), do: :ok

  defp usable_connection(context) do
    case Connections.get(context) do
      nil -> {:error, :channels_not_connected}
      %{status: "invalid"} -> {:error, :channels_connection_invalid}
      %{channels: []} -> {:error, :channels_not_connected}
      connection -> {:ok, connection}
    end
  end

  # ADR-390: no invented cap; until the box types one, nothing is sent.
  defp budget_set(%{monthly_budget_cents: cap}) when is_integer(cap), do: :ok
  defp budget_set(_connection), do: {:error, :channel_budget_missing}

  # A built-in key, or a key only the box wrote (its own wording).
  defp template(context, key) when is_binary(key) do
    rows = ChannelStore.list_templates(context, key)

    case Templates.fetch(key) do
      {:ok, builtin} ->
        {:ok, Map.put(builtin, :rows, rows)}

      :error when rows != [] ->
        {:ok, %{key: key, purpose: nil, variables: [], bodies: %{}, rows: rows}}

      :error ->
        {:error, :channel_template_missing}
    end
  end

  defp template(_context, _key), do: {:error, :channel_template_missing}

  # A built-in template has its purpose; the free texts (`box_message`, the
  # box's own keys) take the caller's, service by default.
  defp purpose(%{purpose: "marketing"}, requested) when requested in [nil, "marketing"],
    do: {:ok, "marketing"}

  defp purpose(%{purpose: "marketing"}, _requested),
    do: {:error, {:invalid_fields, %{purpose: "invalid"}}}

  defp purpose(%{key: key, purpose: fixed}, requested)
       when key != "box_message" and is_binary(fixed) and requested in [nil, fixed],
       do: {:ok, fixed}

  defp purpose(%{key: key, purpose: fixed}, _requested)
       when key != "box_message" and is_binary(fixed),
       do: {:error, {:invalid_fields, %{purpose: "invalid"}}}

  defp purpose(_template, requested) when requested in [nil, "service"], do: {:ok, "service"}
  defp purpose(_template, "marketing"), do: {:ok, "marketing"}
  defp purpose(_template, _requested), do: {:error, {:invalid_fields, %{purpose: "invalid"}}}

  defp contact(context, person) do
    case Contacts.find(context, person) do
      nil -> {:error, :channel_contact_missing}
      contact -> {:ok, contact}
    end
  end

  defp whatsapp_template(template, locale) do
    approved =
      Enum.filter(
        template.rows,
        &(&1.channel == "whatsapp" and &1.approval_status == "approved")
      )

    Enum.find(approved, &(&1.locale == locale)) || Enum.find(approved, &(&1.locale == "en"))
  end

  defp body(_template, "whatsapp", %{body: body, locale: locale}, _contact_locale),
    do: {:ok, {body, locale}}

  defp body(template, _channel, _whatsapp, locale) do
    overrides =
      template.rows
      |> Enum.filter(&(&1.channel == "any"))
      |> Map.new(&{&1.locale, &1.body})

    Templates.body(template.key, locale, overrides)
  end

  defp template_values(%{variable_names: names}, "whatsapp", variables),
    do: Enum.map(names, &to_string(Map.get(variables, &1, "")))

  defp template_values(_whatsapp, _channel, _variables), do: []

  # Marketing SMS end with a short link that withdraws that consent
  # (ADR-390: a named sender cannot receive a STOP reply). Service messages
  # carry no link; Viber and WhatsApp have their own block buttons.
  defp opt_out(text, "marketing", "sms", locale, contact),
    do: text <> Templates.opt_out(locale, Unsubscribe.url(contact.id))

  defp opt_out(text, _purpose, _channel, _locale, _contact), do: text

  defp length_ok(text) do
    if String.length(text) <= MessageText.max_length(),
      do: :ok,
      else: {:error, {:invalid_fields, %{body: "too_long"}}}
  end

  # An alphanumeric SMS sender cannot receive replies, so STOP by SMS only
  # works from a number (ADR-350 §3).
  defp replies_possible?(connection, "sms"),
    do: is_binary(connection.sms_sender) and String.starts_with?(connection.sms_sender, "+")

  defp replies_possible?(_connection, _channel), do: true

  # ── Queuing ─────────────────────────────────────────────────────────────

  @doc """
  Queues a message. `request`:

    * `person` – `{:user, id}` or `{:lead, id}`;
    * `template_key` – a built-in key (`Templates.keys/0`) or the box's own;
    * `variables` – `%{"name" => value}` for the template's placeholders;
    * `purpose` – `service` or `marketing` (fixed by built-in templates);
    * `channels` – the caller's order of preference (else the box's);
    * `urgent` – marks an urgent service message (every service message
      ignores quiet hours, ADR-390);
    * `idempotency_key` – the same key answers the message already queued;
    * `source` (`staff`, `automation`, `system`), `source_ref`, `actor_id`.

  `{:ok, message}` or `{:error, reason}`: `:channels_demo_mode`, `:channels_not_connected`,
  `:channels_connection_invalid`, `:channel_budget_missing`, `:channel_template_missing`,
  `:channel_contact_missing`, `:channel_not_enabled`,
  `:channel_consent_missing`, `:channel_opted_out`,
  `:whatsapp_template_missing`, `:channel_budget_exceeded`,
  `:idempotency_key_reused`, `{:invalid_fields, errors}`.
  """
  def send(context, request, env) do
    case ChannelStore.get_message_by_key(context, request.idempotency_key) do
      nil -> queue(context, request, env)
      existing -> same_request(existing, context, request)
    end
  end

  defp same_request(existing, context, request) do
    contact = Contacts.find(context, request.person)

    if (existing.template_key == request.template_key and contact) &&
         contact.id == existing.contact_id,
       do: {:ok, existing},
       else: {:error, :idempotency_key_reused}
  end

  defp queue(context, request, env) do
    with {:ok, plan} <- prepare(context, request, env) do
      attrs = %{
        contact_id: plan.contact.id,
        channel: plan.channel,
        purpose: plan.purpose,
        template_key: plan.template_key,
        locale: plan.locale,
        body: plan.body,
        template_values: plan.template_values,
        to_phone: plan.contact.phone_e164,
        idempotency_key: request.idempotency_key,
        status: "queued",
        hold_reason: if(plan.held_for_quiet_hours, do: "quiet_hours"),
        urgent: plan.urgent,
        next_attempt_at: plan.release_at,
        provider: plan.connection.provider,
        account_mode: plan.connection.account_mode,
        segments: plan.segments,
        estimated_cost_cents: plan.estimated_cost_cents,
        provider_cost_cents: plan.provider_cost_cents,
        margin_bps: plan.margin_bps,
        currency: plan.currency,
        source: request.source,
        source_ref: request[:source_ref],
        created_by_id: request[:actor_id],
        # The month a message counts against is the one it was queued in,
        # on the same clock as the budget check.
        inserted_at: env.now
      }

      case ChannelStore.insert_message(context, attrs) do
        {:ok, message} ->
          {:ok, message}

        # A concurrent send with the same key won the race.
        {:error, %Ecto.Changeset{errors: errors}} = error ->
          if Keyword.has_key?(errors, :organization_id),
            do:
              same_request(
                ChannelStore.get_message_by_key(context, request.idempotency_key),
                context,
                request
              ),
            else: error
      end
    end
  end

  # ── Delivering ──────────────────────────────────────────────────────────

  @doc """
  Sends what is due (or only `id`): `{:ok, %{sent, failed, retrying,
  cancelled, deferred}}`. Safe to run from several workers at once.
  """
  def deliver(context, which, %DateTime{} = now) do
    context
    |> ChannelStore.claim(which, now, @batch)
    |> Enum.map(&deliver_one(context, &1, now))
    |> Enum.frequencies()
    |> then(&{:ok, Map.merge(%{sent: 0, failed: 0, retrying: 0, cancelled: 0, deferred: 0}, &1)})
  end

  defp deliver_one(context, message, now) do
    connection = Connections.get(context)
    contact = Contacts.get(context, message.contact_id)

    cond do
      is_nil(connection) or connection.status == "invalid" ->
        defer(context, message, "connection", now)

      is_nil(contact) ->
        cancel_with(context, message, "channel_contact_missing", now)

      true ->
        facts = %{
          connection: connection,
          contact: contact,
          consents: contact.consents,
          purpose: message.purpose,
          # Checked when queued; the template id is read again below.
          whatsapp_template?: true
        }

        case ChannelPolicy.allowed(message.channel, facts) do
          :ok -> call_provider(context, message, connection, now)
          {:error, reason} -> cancel_with(context, message, Atom.to_string(reason), now)
        end
    end
  end

  defp call_provider(context, message, connection, now) do
    outgoing = %{
      id: message.id,
      channel: message.channel,
      to: message.to_phone,
      body: message.body,
      purpose: message.purpose,
      template: provider_template(context, message),
      callback_url: Connections.webhook_url(connection)
    }

    result =
      Connections.adapter(connection.provider).send_message(
        Connections.account(connection),
        outgoing
      )

    changes = DeliveryPolicy.outcome(message, result, now)

    event = %{
      kind: "attempt",
      status: DeliveryPolicy.attempt_status(result),
      error_code: changes[:error_code],
      detail: changes[:error_message],
      occurred_at: now
    }

    {:ok, _saved} = ChannelStore.update_message(context, message.id, changes, event)

    if match?({:error, {:unauthorized, _}}, result),
      do: Connections.mark_invalid(context, "credentials_rejected")

    case changes.status do
      "sent" -> :sent
      "failed" -> :failed
      _queued -> :retrying
    end
  end

  defp provider_template(context, %{channel: "whatsapp"} = message) do
    context
    |> ChannelStore.list_templates(message.template_key)
    |> Enum.find(
      &(&1.channel == "whatsapp" and &1.locale == message.locale and
          &1.approval_status == "approved")
    )
    |> case do
      nil ->
        nil

      row ->
        %{
          provider_template_id: row.provider_template_id,
          locale: row.locale,
          values: message.template_values
        }
    end
  end

  defp provider_template(_context, _message), do: nil

  # A missing or refused connection does not spend the message's attempts.
  defp defer(context, message, reason, now) do
    {:ok, _saved} =
      ChannelStore.update_message(
        context,
        message.id,
        %{
          status: "queued",
          hold_reason: reason,
          attempts: max(message.attempts - 1, 0),
          claimed_at: nil,
          next_attempt_at: DateTime.add(now, 900, :second)
        },
        nil
      )

    :deferred
  end

  defp cancel_with(context, message, code, now) do
    {:ok, _saved} =
      ChannelStore.update_message(
        context,
        message.id,
        %{status: "cancelled", claimed_at: nil, next_attempt_at: nil, error_code: code},
        %{kind: "attempt", status: "cancelled", error_code: code, occurred_at: now}
      )

    :cancelled
  end

  # ── Staff actions ───────────────────────────────────────────────────────

  @doc "Sends a failed message again: `{:ok, message}` or `{:error, :channel_not_retryable | :not_found}`."
  def retry(context, id, %DateTime{} = now) do
    case ChannelStore.get_message(context, id) do
      nil ->
        {:error, :not_found}

      message ->
        if DeliveryPolicy.retryable?(message),
          do: ChannelStore.update_message(context, id, DeliveryPolicy.retry(now), nil),
          else: {:error, :channel_not_retryable}
    end
  end

  @doc "Stops a queued message: `{:ok, message}` or `{:error, :not_cancellable | :not_found}`."
  def cancel(context, id, actor_id, %DateTime{} = now) do
    case ChannelStore.get_message(context, id) do
      nil ->
        {:error, :not_found}

      message ->
        if DeliveryPolicy.cancellable?(message),
          do:
            ChannelStore.update_message(
              context,
              id,
              %{status: "cancelled", next_attempt_at: nil, error_code: "cancelled_by_staff"},
              %{
                kind: "attempt",
                status: "cancelled",
                detail: actor_id && "by:" <> actor_id,
                occurred_at: now
              }
            ),
          else: {:error, :not_cancellable}
    end
  end

  @doc "A message with its attempts and receipts, or nil."
  def get(context, id) do
    case ChannelStore.get_message(context, id) do
      nil -> nil
      message -> Map.put(message, :events, ChannelStore.list_events(context, id))
    end
  end

  def list(context, filters), do: ChannelStore.list_messages(context, filters)

  @doc """
  ADR-385: the box's price of one part of a `channel` message to its own
  country (Palee's margin included on Palee's account), for «≈ X € ανά SMS».
  """
  def unit_price(context, channel, purpose) do
    connection = Connections.get(context)
    country = (connection && connection.default_country) || "GR"

    provider =
      CostPolicy.estimate(
        Application.get_env(:palee, :channel_prices),
        channel,
        purpose,
        country,
        1
      )

    margin =
      if connection && connection.account_mode == "palee", do: Margins.bps(channel), else: 0

    CostPolicy.price(provider, margin)
  end

  @counted ~w(queued sending sent delivered)

  @doc """
  ADR-385: what the messages of one `source_ref` (an event, a class) cost the
  box so far, charged as the month's spend is: the provider's charge with
  the message's margin when known, else the estimate.
  """
  def spent_on(context, source_ref) when is_binary(source_ref) do
    context
    |> ChannelStore.list_messages(%{source_ref: source_ref, limit: 1000})
    |> Map.get(:messages, [])
    |> Enum.filter(
      &(&1.status in @counted or (&1.status == "failed" and is_integer(&1.cost_cents)))
    )
    |> Enum.map(fn message ->
      case message.cost_cents do
        cents when is_integer(cents) -> CostPolicy.price(cents, message.margin_bps || 0)
        _unknown -> message.estimated_cost_cents || 0
      end
    end)
    |> Enum.sum()
  end

  @doc "The month's spend (`month` `YYYY-MM` on the box clock, default now) against the cap."
  def usage(context, month, env) do
    range =
      case month do
        nil -> {:ok, CostPolicy.month_range(env.now, env.time_zone)}
        month -> CostPolicy.month_range_of(month, env.time_zone)
      end

    with {:ok, {from, to}} <- range do
      connection = Connections.get(context)
      spend = ChannelStore.spend(context, from, to)

      {:ok,
       %{
         from: from,
         to: to,
         spent_cents: spend.total,
         messages: spend.count,
         segments: spend.segments,
         by_channel: spend.by_channel,
         by_source: spend.by_source,
         by_status: spend.by_status,
         cap_cents: connection && connection.monthly_budget_cents,
         currency: (connection && connection.currency) || "EUR",
         account_mode: connection && connection.account_mode,
         # ADR-369: what Palee bills the box for the month (messages sent
         # on Palee's account, at the box's price).
         palee_charge_cents: spend.palee_charge
       }}
    end
  end

  @doc """
  ADR-369: the box's charge for messages Palee sent on its own account in a
  month (`YYYY-MM` on the box clock), for billing and the Palee team:
  `%{month, from, to, currency, charge_cents, provider_cost_cents,
  margin_cents, messages, by_channel}`. Own-account messages are not in it.
  """
  def monthly_charge(context, month, env) do
    with {:ok, {from, to}} <- CostPolicy.month_range_of(month, env.time_zone) do
      connection = Connections.get(context)
      spend = ChannelStore.spend(context, from, to)

      {:ok,
       %{
         month: month,
         from: from,
         to: to,
         currency: (connection && connection.currency) || "EUR",
         charge_cents: spend.palee_charge,
         provider_cost_cents: spend.provider_total,
         margin_cents: spend.palee_charge - spend.provider_total,
         messages: spend.palee_by_channel |> Map.values() |> Enum.map(& &1.count) |> Enum.sum(),
         by_channel: spend.palee_by_channel
       }}
    end
  end

  # ── Webhook ─────────────────────────────────────────────────────────────

  @doc """
  A call on the box's webhook: checks the URL token, lets the provider's
  adapter verify the signature and read the events, applies receipts once
  each and stops numbers that replied STOP. `{:ok, %{receipts, stops}}`,
  or `{:error, :not_found | :invalid_signature}`.
  """
  def handle_webhook(context, token, request, %DateTime{} = now) do
    with %{} = connection <- Connections.get(context) || {:error, :not_found},
         true <- Connections.valid_webhook_token?(connection, token) || {:error, :not_found},
         {:ok, events} <-
           Connections.adapter(connection.provider).parse_webhook(
             Connections.account(connection),
             Map.put(request, :url, Connections.webhook_url(connection))
           ) do
      Enum.reduce(events, {:ok, %{receipts: 0, stops: 0}}, fn event, {:ok, counts} ->
        {:ok, apply_event(context, connection, event, counts, now)}
      end)
    end
  end

  defp apply_event(context, connection, %{type: :status} = event, counts, now) do
    case ChannelStore.get_message_by_provider_id(
           context,
           connection.provider,
           event.provider_message_id
         ) do
      nil ->
        counts

      message ->
        result =
          ChannelStore.transaction(context, fn ->
            receipt(context, message, event, now)
          end)

        if match?({:ok, :applied}, result),
          do: Map.update!(counts, :receipts, &(&1 + 1)),
          else: counts
    end
  end

  defp apply_event(context, connection, %{type: :inbound, text: text, from: from}, counts, now) do
    with true <- ChannelPolicy.stop_keyword?(text),
         {:ok, phone} <- PhoneNumber.normalize(from, connection.default_country),
         {:ok, stopped} <- Contacts.stop(context, phone, now) do
      Map.update!(counts, :stops, &(&1 + stopped))
    else
      _not_a_stop -> counts
    end
  end

  defp apply_event(_context, _connection, _event, counts, _now), do: counts

  defp receipt(context, message, event, now) do
    with {:ok, %{}} <-
           ChannelStore.record_event(context, %{
             message_id: message.id,
             kind: "receipt",
             status: event.status,
             provider_status: event.provider_status,
             error_code: event.error_code,
             event_key: event.event_key,
             occurred_at: event.occurred_at || now
           }) do
      case DeliveryPolicy.receipt(message, event, now) do
        nil ->
          {:ok, :applied}

        changes ->
          with {:ok, _message} <- ChannelStore.update_message(context, message.id, changes, nil) do
            {:ok, :applied}
          end
      end
    else
      {:ok, :duplicate} -> {:ok, :duplicate}
      error -> error
    end
  end
end
