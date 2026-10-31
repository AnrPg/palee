defmodule Palee.Integrations.AudienceMember do
  @moduledoc "What Palee last told the list about a member (ADR-380): a hash, never the email."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(connection_id user_id email_hash status synced_at last_error)a

  schema "audience_members" do
    field :organization_id, :binary_id, read_after_writes: true
    field :connection_id, :binary_id
    field :user_id, :binary_id
    field :email_hash, :string
    field :status, :string
    field :synced_at, :utc_datetime_usec
    field :last_error, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, @fields)
    |> validate_required([:connection_id, :user_id, :email_hash, :status, :synced_at])
  end
end
