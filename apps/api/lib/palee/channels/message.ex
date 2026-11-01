defmodule Palee.Channels.Message do
  @moduledoc "The outbox row of one SMS, Viber or WhatsApp message (ADR-348 §5)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(contact_id channel purpose template_key locale body template_values to_phone idempotency_key status
             hold_reason urgent attempts next_attempt_at claimed_at provider account_mode
             provider_message_id segments estimated_cost_cents provider_cost_cents margin_bps
             cost_cents currency error_code
             error_message source source_ref created_by_id sent_at delivered_at failed_at)a

  schema "channel_messages" do
    field :organization_id, :binary_id, read_after_writes: true
    field :contact_id, :binary_id
    field :channel, :string
    field :purpose, :string
    field :template_key, :string
    field :locale, :string
    field :body, :string
    # ADR-350: the values of an approved WhatsApp template, in its order.
    field :template_values, {:array, :string}, default: []
    field :to_phone, :string
    field :idempotency_key, :string
    field :status, :string, default: "queued"
    field :hold_reason, :string
    field :urgent, :boolean, default: false
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :provider, :string
    field :account_mode, :string
    field :provider_message_id, :string
    field :segments, :integer, default: 1
    # ADR-369: the box's price (provider estimate plus Palee's margin on a
    # Palee-managed account), the provider estimate and the margin applied.
    field :estimated_cost_cents, :integer, default: 0
    field :provider_cost_cents, :integer
    field :margin_bps, :integer, default: 0
    field :cost_cents, :integer
    field :currency, :string, default: "EUR"
    field :error_code, :string
    field :error_message, :string
    field :source, :string
    field :source_ref, :string
    field :created_by_id, :binary_id
    field :sent_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :failed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, @fields)
    |> validate_required([
      :contact_id,
      :channel,
      :purpose,
      :template_key,
      :locale,
      :body,
      :to_phone,
      :idempotency_key,
      :status,
      :provider,
      :account_mode,
      :source
    ])
    |> unique_constraint([:organization_id, :idempotency_key])
    |> unique_constraint([:provider, :provider_message_id],
      name: :channel_messages_provider_message_index
    )
    |> check_constraint(:status, name: :channel_messages_check)
  end
end
