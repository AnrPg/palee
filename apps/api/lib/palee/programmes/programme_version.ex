defmodule Palee.Programmes.ProgrammeVersion do
  @moduledoc """
  A published version of a programme (ADR-370): its weeks and, per day,
  the frozen copy of each WOD (`workout_id`) with the WOD it was copied
  from (`source_workout_id`) and a short summary for previews. Immutable.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "programme_versions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :programme_id, :binary_id
    field :number, :integer
    field :weeks, :integer
    field :days, {:array, :map}
    field :changelog, :string
    field :published_at, :utc_datetime_usec
    field :published_by_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :programme_id,
      :number,
      :weeks,
      :days,
      :changelog,
      :published_at,
      :published_by_id
    ])
    |> validate_required([:programme_id, :number, :weeks, :days, :published_at])
    |> validate_length(:changelog, max: 600)
    |> unique_constraint([:programme_id, :number])
    |> check_constraint(:weeks, name: :programme_versions_check)
  end
end
