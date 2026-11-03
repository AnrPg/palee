defmodule Palee.Integrations.IdempotencyRecord do
  @moduledoc "ADR-300's `Idempotency-Key`: the first answer of a command, kept for a day."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(principal key operation request_hash state response_status response_body
             expires_at)a

  schema "idempotency_records" do
    field :organization_id, :binary_id, read_after_writes: true
    field :principal, :string
    field :key, :string
    field :operation, :string
    field :request_hash, :string
    field :state, :string, default: "in_progress"
    field :response_status, :integer
    field :response_body, :map
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, @fields)
    |> validate_required([:principal, :key, :operation, :request_hash, :expires_at])
    |> unique_constraint([:organization_id, :principal, :key])
  end
end
