defmodule Palee.Infrastructure.Channels.EctoChannelStore do
  @moduledoc "Ecto adapter of the channel store (ADR-348)."

  @behaviour Palee.Channels.Ports.ChannelStore

  import Ecto.Query

  alias Palee.Channels.{
    Connection,
    Consent,
    Contact,
    EmailConnection,
    Message,
    MessageEvent,
    PlatformSetting,
    Template
  }

  alias Palee.Channels.Domain.DeliveryPolicy
  alias Palee.Repo

  @max_page 200

  @impl true
  def transaction(_context, fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Connection ──────────────────────────────────────────────────────────

  @impl true
  def get_connection(%{organization_id: organization_id}) do
    Connection
    |> where([c], c.organization_id == ^organization_id)
    |> Repo.one()
    |> to_map()
  end

  @impl true
  def save_connection(%{organization_id: organization_id}, attrs) do
    case Repo.one(from c in Connection, where: c.organization_id == ^organization_id) do
      nil -> %Connection{organization_id: organization_id}
      connection -> connection
    end
    |> Connection.changeset(attrs)
    |> Repo.insert_or_update()
    |> result()
  end

  # ── Own SMTP email provider (ADR-368) ──────────────────────────────────

  @impl true
  def get_email_connection(%{organization_id: organization_id}) do
    EmailConnection
    |> where([c], c.organization_id == ^organization_id)
    |> Repo.one()
    |> to_map()
  end

  @impl true
  def save_email_connection(%{organization_id: organization_id}, attrs) do
    case Repo.one(from c in EmailConnection, where: c.organization_id == ^organization_id) do
      nil -> %EmailConnection{organization_id: organization_id}
      connection -> connection
    end
    |> EmailConnection.changeset(attrs)
    |> Repo.insert_or_update()
    |> result()
  end

  @impl true
  def delete_email_connection(%{organization_id: organization_id}) do
    EmailConnection
    |> where([c], c.organization_id == ^organization_id)
    |> Repo.delete_all()

    :ok
  end

  # ── Platform settings (ADR-369) ─────────────────────────────────────────

  @impl true
  def get_platform_settings, do: PlatformSetting |> Repo.one() |> to_map()

  @impl true
  def save_platform_settings(attrs) do
    (Repo.one(PlatformSetting) || %PlatformSetting{})
    |> PlatformSetting.changeset(attrs)
    |> Repo.insert_or_update()
    |> result()
  end

  # ── Contacts and consents ───────────────────────────────────────────────

  @impl true
  def get_contact(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Contact
      |> where([c], c.organization_id == ^organization_id and c.id == ^id)
      |> Repo.one()
      |> to_map()
    else
      :error -> nil
    end
  end

  @impl true
  def find_contact(context, person),
    do: context |> contact_query(person) |> Repo.one() |> to_map()

  defp contact_query(%{organization_id: organization_id}, {:user, user_id}),
    do: where(Contact, [c], c.organization_id == ^organization_id and c.user_id == ^user_id)

  defp contact_query(%{organization_id: organization_id}, {:lead, lead_id}),
    do: where(Contact, [c], c.organization_id == ^organization_id and c.lead_id == ^lead_id)

  @impl true
  def save_contact(context, person, attrs) do
    case context |> contact_query(person) |> Repo.one() do
      nil ->
        %Contact{organization_id: context.organization_id}
        |> Contact.changeset(Map.merge(person_attrs(person), attrs))

      contact ->
        Contact.changeset(contact, attrs)
    end
    |> Repo.insert_or_update()
    |> result()
  end

  defp person_attrs({:user, id}), do: %{user_id: id}
  defp person_attrs({:lead, id}), do: %{lead_id: id}

  @impl true
  def delete_contact(%{organization_id: organization_id}, id) do
    Contact
    |> where([c], c.organization_id == ^organization_id and c.id == ^id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def delete_person(context, person) do
    context |> contact_query(person) |> Repo.delete_all()
    :ok
  end

  @impl true
  def contacts_by_phone(%{organization_id: organization_id}, phone) do
    Contact
    |> where([c], c.organization_id == ^organization_id and c.phone_e164 == ^phone)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  @impl true
  def list_contacts(%{organization_id: organization_id}, filters) do
    Contact
    |> where([c], c.organization_id == ^organization_id)
    |> then(fn query ->
      case filters[:user_ids] do
        nil -> query
        ids -> where(query, [c], c.user_id in ^ids)
      end
    end)
    |> then(fn query ->
      case filters[:lead_ids] do
        nil -> query
        ids -> where(query, [c], c.lead_id in ^ids)
      end
    end)
    |> order_by([c], desc: c.updated_at)
    |> limit(^min(filters[:limit] || 100, @max_page))
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  @impl true
  def list_consents(_context, []), do: []

  def list_consents(%{organization_id: organization_id}, contact_ids) do
    Consent
    |> where([c], c.organization_id == ^organization_id and c.contact_id in ^contact_ids)
    |> order_by([c], asc: c.channel, asc: c.purpose)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  @impl true
  def put_consent(%{organization_id: organization_id}, contact_id, channel, purpose, attrs) do
    case Repo.one(
           from c in Consent,
             where:
               c.organization_id == ^organization_id and c.contact_id == ^contact_id and
                 c.channel == ^channel and c.purpose == ^purpose
         ) do
      nil ->
        %Consent{organization_id: organization_id}
        |> Consent.changeset(
          Map.merge(attrs, %{contact_id: contact_id, channel: channel, purpose: purpose})
        )

      consent ->
        Consent.changeset(consent, attrs)
    end
    |> Repo.insert_or_update()
    |> result()
  end

  # ── Templates ───────────────────────────────────────────────────────────

  @impl true
  def list_templates(%{organization_id: organization_id}, key) do
    Template
    |> where([t], t.organization_id == ^organization_id)
    |> then(fn query -> if key, do: where(query, [t], t.key == ^key), else: query end)
    |> order_by([t], asc: t.key, asc: t.locale, asc: t.channel)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  @impl true
  def save_template(%{organization_id: organization_id}, attrs) do
    case Repo.one(
           from t in Template,
             where:
               t.organization_id == ^organization_id and t.key == ^attrs.key and
                 t.locale == ^attrs.locale and t.channel == ^attrs.channel
         ) do
      nil -> %Template{organization_id: organization_id}
      template -> template
    end
    |> Template.changeset(attrs)
    |> Repo.insert_or_update()
    |> result()
  end

  @impl true
  def delete_template(%{organization_id: organization_id}, key, locale, channel) do
    Template
    |> where(
      [t],
      t.organization_id == ^organization_id and t.key == ^key and t.locale == ^locale and
        t.channel == ^channel
    )
    |> Repo.delete_all()

    :ok
  end

  # ── Outbox ──────────────────────────────────────────────────────────────

  @impl true
  def insert_message(_context, attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Ecto.Changeset.put_change(:inserted_at, attrs[:inserted_at])
    |> Repo.insert()
    |> result()
  end

  @impl true
  def get_message(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Message
      |> where([m], m.organization_id == ^organization_id and m.id == ^id)
      |> Repo.one()
      |> to_map()
    else
      :error -> nil
    end
  end

  @impl true
  def get_message_by_key(%{organization_id: organization_id}, key) do
    Message
    |> where([m], m.organization_id == ^organization_id and m.idempotency_key == ^key)
    |> Repo.one()
    |> to_map()
  end

  @impl true
  def get_message_by_provider_id(%{organization_id: organization_id}, provider, provider_id) do
    Message
    |> where(
      [m],
      m.organization_id == ^organization_id and m.provider == ^provider and
        m.provider_message_id == ^provider_id
    )
    |> Repo.one()
    |> to_map()
  end

  @impl true
  def claim(%{organization_id: organization_id}, which, %DateTime{} = now, limit) do
    stale = DateTime.add(now, -DeliveryPolicy.claim_timeout_seconds(), :second)

    candidates =
      Message
      |> where([m], m.organization_id == ^organization_id)
      |> where(
        [m],
        (m.status == "queued" and m.next_attempt_at <= ^now) or
          (m.status == "sending" and m.claimed_at < ^stale)
      )
      |> then(fn query ->
        case which do
          :due -> query
          id -> where(query, [m], m.id == ^id)
        end
      end)
      |> order_by([m], asc: m.next_attempt_at)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> select([m], m.id)

    {_count, rows} =
      Message
      |> where([m], m.id in subquery(candidates))
      |> select([m], m)
      |> Repo.update_all(
        set: [status: "sending", claimed_at: now, updated_at: DateTime.utc_now()],
        inc: [attempts: 1]
      )

    Enum.map(rows, &to_map/1)
  end

  @impl true
  def update_message(%{organization_id: organization_id}, id, changes, event) do
    Repo.transaction(fn ->
      with %Message{} = message <-
             Repo.one(
               from m in Message,
                 where: m.organization_id == ^organization_id and m.id == ^id,
                 lock: "FOR UPDATE"
             ) || {:error, :not_found},
           {:ok, updated} <- message |> Message.changeset(changes) |> Repo.update(),
           :ok <- insert_event(event, id) do
        to_map(updated)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_event(nil, _id), do: :ok

  defp insert_event(event, id) do
    case event |> Map.put(:message_id, id) |> MessageEvent.changeset() |> Repo.insert() do
      {:ok, _event} -> :ok
      error -> error
    end
  end

  # `on_conflict: :nothing` through insert_all: with a client-generated id,
  # Repo.insert cannot tell a skipped row from an inserted one.
  @impl true
  def record_event(_context, attrs) do
    case attrs |> MessageEvent.changeset() |> Ecto.Changeset.apply_action(:insert) do
      {:ok, event} ->
        row =
          event
          |> Map.take(MessageEvent.__schema__(:fields) -- [:organization_id])
          |> Map.merge(%{id: Ecto.UUID.generate(), inserted_at: DateTime.utc_now()})

        case Repo.insert_all(MessageEvent, [row],
               on_conflict: :nothing,
               conflict_target: {:unsafe_fragment, conflict_target()},
               returning: true
             ) do
          {1, [inserted]} -> {:ok, to_map(inserted)}
          {0, []} -> {:ok, :duplicate}
        end

      error ->
        error
    end
  end

  defp conflict_target, do: "(organization_id, event_key) WHERE event_key IS NOT NULL"

  @impl true
  def list_messages(%{organization_id: organization_id}, filters) do
    query =
      Message
      |> where([m], m.organization_id == ^organization_id)
      |> filter(:status, filters[:status])
      |> filter(:contact_id, filters[:contact_id])
      |> filter(:channel, filters[:channel])
      |> filter(:source_ref, filters[:source_ref])

    %{
      messages:
        query
        |> order_by([m], desc: m.inserted_at, desc: m.id)
        |> limit(^min(filters[:limit] || 50, @max_page))
        |> offset(^(filters[:offset] || 0))
        |> Repo.all()
        |> Enum.map(&to_map/1),
      total: Repo.aggregate(query, :count)
    }
  end

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [m], field(m, ^field) == ^value)

  @impl true
  def list_events(%{organization_id: organization_id}, id) do
    MessageEvent
    |> where([e], e.organization_id == ^organization_id and e.message_id == ^id)
    |> order_by([e], asc: e.occurred_at, asc: e.inserted_at)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  # Queued messages count too: the cap must hold for what is waiting.
  @counted ~w(queued sending sent delivered)

  @impl true
  def spend(%{organization_id: organization_id}, %DateTime{} = from, %DateTime{} = to) do
    rows =
      Message
      |> where([m], m.organization_id == ^organization_id)
      |> where([m], m.inserted_at >= ^from and m.inserted_at < ^to)
      |> where([m], m.status in ^@counted or (m.status == "failed" and not is_nil(m.cost_cents)))
      |> group_by([m], [m.channel, m.account_mode, m.source])
      # ADR-369: the box price is the charged provider price with the
      # message's margin (rounded up, as `CostPolicy.price/2`), else the
      # estimated box price.
      |> select(
        [m],
        {m.channel, m.account_mode, m.source,
         sum(
           coalesce(
             fragment(
               "(? * (10000 + ?) + 9999) / 10000",
               m.cost_cents,
               m.margin_bps
             ),
             m.estimated_cost_cents
           )
         ), sum(coalesce(m.cost_cents, coalesce(m.provider_cost_cents, m.estimated_cost_cents))),
         count(m.id), sum(m.segments)}
      )
      |> Repo.all()
      |> Enum.map(fn {channel, mode, source, cents, provider, count, segments} ->
        %{
          channel: channel,
          mode: mode,
          source: source,
          cents: to_int(cents),
          provider: to_int(provider),
          count: count,
          segments: to_int(segments)
        }
      end)

    palee = Enum.filter(rows, &(&1.mode == "palee"))

    %{
      total: rows |> Enum.map(& &1.cents) |> Enum.sum(),
      count: rows |> Enum.map(& &1.count) |> Enum.sum(),
      segments: rows |> Enum.map(& &1.segments) |> Enum.sum(),
      by_channel: sum_by(rows, & &1.channel),
      # ADR-385: who spent it («Αυτοματισμοί», «Staff», the system).
      by_source: sum_by(rows, &(&1.source || "system")),
      by_status: status_counts(organization_id, from, to),
      palee_charge: palee |> Enum.map(& &1.cents) |> Enum.sum(),
      provider_total: palee |> Enum.map(& &1.provider) |> Enum.sum(),
      palee_by_channel:
        palee
        |> Map.new(fn row ->
          {row.channel,
           %{charge_cents: row.cents, provider_cost_cents: row.provider, count: row.count}}
        end)
    }
  end

  defp sum_by(rows, key) do
    rows
    |> Enum.group_by(key)
    |> Map.new(fn {name, group} ->
      {name,
       %{
         cents: group |> Enum.map(& &1.cents) |> Enum.sum(),
         count: group |> Enum.map(& &1.count) |> Enum.sum()
       }}
    end)
  end

  # ADR-385: every message of the range by state, charged or not, so the
  # cost screen can say how many arrived and how many did not.
  defp status_counts(organization_id, from, to) do
    Message
    |> where([m], m.organization_id == ^organization_id)
    |> where([m], m.inserted_at >= ^from and m.inserted_at < ^to)
    |> group_by([m], m.status)
    |> select([m], {m.status, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_int(value) when is_integer(value), do: value

  defp result({:ok, struct}), do: {:ok, to_map(struct)}
  defp result(error), do: error

  defp to_map(nil), do: nil
  defp to_map(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])
end
