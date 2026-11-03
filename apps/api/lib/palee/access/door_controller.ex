defmodule Palee.Access.DoorController do
  @moduledoc """
  A door of a branch and the controller that opens it (ADR-381).
  `credentials` (JSON of the provider's secrets) is encrypted at rest and
  never returned; `event_token_hash` checks the provider's own events.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(location_id name provider settings rules credentials event_token_hash status
             last_error last_seen_at updated_by_id)a

  schema "door_controllers" do
    field :organization_id, :binary_id, read_after_writes: true
    field :location_id, :binary_id
    field :name, :string
    field :provider, :string
    field :settings, :map, default: %{}
    field :rules, :map, default: %{}
    field :credentials, EncryptedBinary, redact: true
    field :event_token_hash, :binary, redact: true
    field :status, :string, default: "active"
    field :last_error, :string
    field :last_seen_at, :utc_datetime_usec
    field :updated_by_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(door, attrs) do
    door
    |> cast(attrs, @fields)
    |> validate_required([:location_id, :name, :provider, :status])
    |> validate_length(:name, min: 1, max: 80)
    |> check_constraint(:provider, name: :door_controllers_check)
    |> foreign_key_constraint(:location_id, name: :door_controllers_location_fkey)
  end
end
