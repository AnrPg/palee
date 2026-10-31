defmodule Palee.Automations.BoxAutomation do
  @moduledoc "ADR-346: a box's choice about one ready recipe: on or off, and what it changed."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Automations.Domain.RecipeCatalog

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "box_automations" do
    field :organization_id, :binary_id, read_after_writes: true
    field :recipe, :string
    field :enabled, :boolean, default: false
    field :channels, {:array, :string}, default: []
    field :delay_minutes, :integer
    field :subject, :string
    field :body, :string
    field :settings, :map, default: %{}
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(automation, params) do
    automation
    |> cast(params, [
      :recipe,
      :enabled,
      :channels,
      :delay_minutes,
      :subject,
      :body,
      :settings,
      :updated_by_id
    ])
    |> validate_required([:recipe])
    |> validate_inclusion(:recipe, RecipeCatalog.keys())
    |> validate_number(:delay_minutes, greater_than_or_equal_to: 0, less_than_or_equal_to: 43_200)
    |> unique_constraint([:organization_id, :recipe])
  end
end
