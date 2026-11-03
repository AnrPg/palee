defmodule Palee.Access.AccessEvent do
  @moduledoc "One line of the door log (ADR-381): who, which door, granted or why not."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(door_controller_id location_id user_id actor_id kind reason method provider_event
             occurred_at)a

  schema "access_events" do
    field :organization_id, :binary_id, read_after_writes: true
    field :door_controller_id, :binary_id
    field :location_id, :binary_id
    field :user_id, :binary_id
    field :actor_id, :binary_id
    field :kind, :string
    field :reason, :string
    field :method, :string
    field :provider_event, :string
    field :occurred_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, @fields)
    |> validate_required([:kind, :reason, :occurred_at])
    |> check_constraint(:kind, name: :access_events_check)
  end
end
