defmodule Palee.Integrations.ApiKey do
  @moduledoc "A box's public API key (ADR-378): the hash of the token, never the token."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(name prefix secret_hash previous_secret_hash previous_expires_at scopes
             created_by_id last_used_at expires_at rotated_at revoked_at revoked_by_id)a

  schema "api_keys" do
    field :organization_id, :binary_id, read_after_writes: true
    field :name, :string
    field :prefix, :string
    field :secret_hash, :binary, redact: true
    field :previous_secret_hash, :binary, redact: true
    field :previous_expires_at, :utc_datetime_usec
    field :scopes, {:array, :string}, default: []
    field :created_by_id, :binary_id
    field :last_used_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :rotated_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :revoked_by_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(key, attrs) do
    key
    |> cast(attrs, @fields)
    |> validate_required([:name, :prefix, :secret_hash, :scopes])
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint(:prefix)
    |> check_constraint(:scopes, name: :api_keys_check)
  end
end
