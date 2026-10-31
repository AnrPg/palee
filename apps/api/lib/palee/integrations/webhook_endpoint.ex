defmodule Palee.Integrations.WebhookEndpoint do
  @moduledoc """
  Where a box's events are sent (ADR-379). `secret` signs every delivery;
  it is encrypted at rest and shown once, when the endpoint is made or its
  secret rotated.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(url description events secret previous_secret previous_secret_expires_at status
             source api_key_id created_by_id consecutive_failures disabled_reason
             last_success_at last_failure_at)a

  schema "webhook_endpoints" do
    field :organization_id, :binary_id, read_after_writes: true
    field :url, :string
    field :description, :string
    field :events, {:array, :string}, default: []
    field :secret, EncryptedBinary, redact: true
    field :previous_secret, EncryptedBinary, redact: true
    field :previous_secret_expires_at, :utc_datetime_usec
    field :status, :string, default: "active"
    field :source, :string, default: "staff"
    field :api_key_id, :binary_id
    field :created_by_id, :binary_id
    field :consecutive_failures, :integer, default: 0
    field :disabled_reason, :string
    field :last_success_at, :utc_datetime_usec
    field :last_failure_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, @fields)
    |> validate_required([:url, :events, :secret, :status, :source])
    |> validate_length(:description, max: 200)
    |> check_constraint(:events, name: :webhook_endpoints_check)
  end
end
