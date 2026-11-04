defmodule Palee.Scheduling.ClassType do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # ADR-460: the levels a class type can suit, in their display order. A class
  # type keeps a subset; an empty list means «Όλα τα επίπεδα».
  @levels ~w(beginner intermediate advanced)
  @audiences ~w(women_only teens kids over_40 seniors prenatal_postnatal adaptive)

  def levels, do: @levels

  schema "class_types" do
    field :organization_id, :binary_id
    field :name, :string
    field :slug, :string
    field :sort_order, :integer, default: 0
    field :archived_at, :utc_datetime
    field :credit_cost, :integer, default: 1
    field :kind, :string, default: "class"
    # Phase 2 schedule filters; no levels means every level (ADR-460) and no
    # audiences means open to everyone. The old single `level` column is unused.
    field :levels, {:array, :string}, default: []
    field :audiences, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end

  def create_changeset(class_type \\ %__MODULE__{}, params) do
    class_type
    |> cast(params, [
      :organization_id,
      :name,
      :slug,
      :sort_order,
      :credit_cost,
      :kind,
      :levels,
      :audiences
    ])
    |> validate_required([:organization_id, :name, :slug, :sort_order])
    |> validate_phase_b()
    |> validate_length(:name, min: 2, max: 80)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
    |> unique_constraint([:organization_id, :slug], name: :class_types_organization_slug_index)
  end

  def update_changeset(class_type, params) do
    class_type
    |> cast(params, [:name, :sort_order, :credit_cost, :kind, :levels, :audiences])
    |> validate_required([:name, :sort_order])
    |> validate_phase_b()
    |> validate_length(:name, min: 2, max: 80)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
  end

  # ADR-097: credit weighting and event classes; Phase 2 level and audience tags.
  defp validate_phase_b(changeset) do
    changeset
    |> validate_number(:credit_cost, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_inclusion(:kind, ["class", "event"])
    |> update_change(:levels, &canonical_levels/1)
    |> validate_subset(:levels, @levels)
    |> update_change(:audiences, &Enum.uniq/1)
    |> validate_subset(:audiences, @audiences)
  end

  # One order everywhere, so equal choices compare equal; unknown values stay
  # for validate_subset to refuse.
  defp canonical_levels(levels) do
    levels = Enum.uniq(levels)
    Enum.filter(@levels, &(&1 in levels)) ++ Enum.reject(levels, &(&1 in @levels))
  end

  def archive_changeset(class_type, archived_at) do
    change(class_type, archived_at: archived_at)
  end
end
