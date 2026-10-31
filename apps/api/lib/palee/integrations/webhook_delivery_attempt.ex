defmodule Palee.Integrations.WebhookDeliveryAttempt do
  @moduledoc "Insert-only log of every call made for a delivery (ADR-379)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(delivery_id attempt outcome status_code error response_excerpt duration_ms
             started_at)a

  schema "webhook_delivery_attempts" do
    field :organization_id, :binary_id, read_after_writes: true
    field :delivery_id, :binary_id
    field :attempt, :integer
    field :outcome, :string
    field :status_code, :integer
    field :error, :string
    field :response_excerpt, :string
    field :duration_ms, :integer
    field :started_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, @fields)
    |> validate_required([:delivery_id, :attempt, :outcome, :started_at])
  end
end
