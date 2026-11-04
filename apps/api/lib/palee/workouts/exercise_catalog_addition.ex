defmodule Palee.Workouts.ExerciseCatalogAddition do
  @moduledoc """
  ADR-461: what the Palee team added to the WOD editors' exercise catalog:
  a new entry (`kind` `entry`, its slug, label and category) or an alias of
  an existing entry (`kind` `alias`, the entry's slug and the alias). Only
  these, with the built-in catalog, are the «Palee» suggestions.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "exercise_catalog_additions" do
    field :kind, :string
    field :catalog_slug, :string
    field :label, :string
    field :folded, :string
    field :category, :string
    field :candidate_id, :binary_id
    field :approved_by_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
