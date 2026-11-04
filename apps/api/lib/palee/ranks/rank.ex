defmodule Palee.Ranks.Rank do
  @moduledoc "One step of a ladder: a belt or a level, with what it takes (ADR-377)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "ranks" do
    field(:organization_id, :binary_id)
    field(:ladder_id, :binary_id)
    field(:position, :integer)
    field(:name, :string)
    field(:color, :string)
    field(:max_stripes, :integer, default: 0)
    field(:requirements, :map, default: %{})
    field(:scale_level_slug, :string)

    timestamps(type: :utc_datetime_usec)
  end
end
