defmodule Palee.Status.IncidentUpdate do
  @moduledoc "ADR-364: one step in an incident's timeline: its status then and the note people read."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "status_incident_updates" do
    field :incident_id, :binary_id
    field :status, :string
    field :body, :string
    field :notify, :boolean, default: true
    field :created_by_id, :binary_id
    # ADR-366: the language the note was written in and its English version.
    field :locale, :string
    field :body_en, :string
    field :en_source, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:incident_id, :status, :body, :notify, :created_by_id, :locale, :body_en, :en_source])
    |> validate_required([:incident_id, :status, :body])
    |> check_constraint(:body, name: :status_incident_updates_body_check)
    |> check_constraint(:body_en, name: :status_incident_updates_translation_check)
  end
end
