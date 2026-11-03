defmodule Palee.Integrations.WebhookDelivery do
  @moduledoc "One event on its way to one endpoint: the outbox row (ADR-379)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(endpoint_id event_id event_type payload status attempts next_attempt_at
             claimed_at last_status_code last_error delivered_at replay_of_id)a

  schema "webhook_deliveries" do
    field :organization_id, :binary_id, read_after_writes: true
    field :endpoint_id, :binary_id
    field :event_id, :binary_id
    field :event_type, :string
    field :payload, :map
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :last_status_code, :integer
    field :last_error, :string
    field :delivered_at, :utc_datetime_usec
    field :replay_of_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, @fields)
    |> validate_required([:endpoint_id, :event_id, :event_type, :payload, :status])
    |> check_constraint(:status, name: :webhook_deliveries_check)
  end
end
