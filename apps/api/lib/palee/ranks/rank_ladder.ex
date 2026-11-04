defmodule Palee.Ranks.RankLadder do
  @moduledoc "A box's ladder of belts or levels for one discipline (ADR-377)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Ranks.Domain.LadderPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "rank_ladders" do
    field(:organization_id, :binary_id)
    field(:name, :string)
    field(:discipline, :string)
    field(:style, :string, default: "belt")
    field(:class_type_ids, {:array, :binary_id}, default: [])
    field(:position, :integer, default: 0)
    field(:ready_criteria, {:array, :string}, default: ["classes", "days"])
    field(:archived_at, :utc_datetime_usec)
    has_many(:ranks, Palee.Ranks.Rank, foreign_key: :ladder_id, preload_order: [asc: :position])

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ladder \\ %__MODULE__{}, attrs) do
    ladder
    |> cast(attrs, [
      :organization_id,
      :name,
      :discipline,
      :style,
      :class_type_ids,
      :position,
      :ready_criteria
    ])
    |> validate_required([:organization_id, :name, :discipline, :style])
    |> update_change(:name, &String.trim/1)
    |> validate_length(:name, min: 1, max: 60)
    |> validate_inclusion(:discipline, LadderPolicy.disciplines())
    |> validate_inclusion(:style, LadderPolicy.styles())
    |> validate_length(:class_type_ids, max: 20)
    |> validate_length(:ready_criteria, min: 1)
    |> validate_subset(:ready_criteria, LadderPolicy.ready_criteria())
    |> unique_constraint(:name, name: :rank_ladders_organization_name_index)
  end

  def archive_changeset(ladder, now), do: change(ladder, archived_at: now)
end
