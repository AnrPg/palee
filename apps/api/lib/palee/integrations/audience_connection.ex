defmodule Palee.Integrations.AudienceConnection do
  @moduledoc """
  The box's email-marketing list (ADR-380): Mailchimp audience or Brevo
  list. `credentials` is the provider's API key, encrypted, never returned;
  `unsubscribe_token_hash` checks the provider's unsubscribe calls.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(provider list_id credentials status last_error last_synced_at sync_requested_at
             claimed_at updated_by_id unsubscribe_token_hash)a

  schema "audience_connections" do
    field :organization_id, :binary_id, read_after_writes: true
    field :provider, :string
    field :list_id, :string
    field :credentials, EncryptedBinary, redact: true
    field :status, :string, default: "active"
    field :last_error, :string
    field :last_synced_at, :utc_datetime_usec
    field :sync_requested_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :updated_by_id, :binary_id
    field :unsubscribe_token_hash, :binary, redact: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, @fields)
    |> validate_required([:provider, :list_id, :status])
    |> unique_constraint(:organization_id)
    |> check_constraint(:provider, name: :audience_connections_check)
  end
end
