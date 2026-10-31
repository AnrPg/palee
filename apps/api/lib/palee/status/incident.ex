defmodule Palee.Status.Incident do
  @moduledoc """
  ADR-364: an incident or a planned maintenance on the status page, with
  its timeline (`updates`, oldest first when preloaded by the store).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Status.IncidentUpdate

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "status_incidents" do
    field :kind, :string
    field :title, :string
    field :impact, :string
    field :status, :string
    field :components, {:array, :string}, default: []
    field :scheduled_for, :utc_datetime_usec
    field :scheduled_until, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :created_by_id, :binary_id

    has_many :updates, IncidentUpdate, preload_order: [asc: :inserted_at]

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(kind title impact status components scheduled_for scheduled_until started_at resolved_at created_by_id)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required([:kind, :title, :impact, :status, :started_at])
    |> check_constraint(:status, name: :status_incidents_check)
  end

  def change_changeset(incident, attrs) do
    incident
    |> cast(attrs, [:title, :impact, :status, :components, :started_at, :resolved_at])
    |> check_constraint(:status, name: :status_incidents_check)
  end
end
