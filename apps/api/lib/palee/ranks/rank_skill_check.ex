defmodule Palee.Ranks.RankSkillCheck do
  @moduledoc """
  A skill of a rank a coach ticked for one person (ADR-400), between
  promotions. Unticking deletes the row. `skill_id` is the skill's stable
  id on the rank (`requirements.skill_ids`); `skill` keeps its text when
  ticked, for the person's data export.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "rank_skill_checks" do
    field(:organization_id, :binary_id)
    field(:user_id, :binary_id)
    field(:rank_id, :binary_id)
    field(:skill_id, :binary_id)
    field(:skill, :string)
    field(:checked_on, :date)
    field(:checked_by_id, :binary_id)
    field(:note, :string)
    field(:notified_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(organization_id user_id rank_id skill_id skill checked_on checked_by_id note notified_at)a

  def changeset(check \\ %__MODULE__{}, attrs) do
    check
    |> cast(attrs, @fields)
    |> validate_required([:organization_id, :user_id, :rank_id, :skill_id, :skill, :checked_on])
    |> validate_length(:skill, max: 120)
    |> validate_length(:note, max: 280)
    |> unique_constraint([:organization_id, :user_id, :rank_id, :skill_id],
      name: :rank_skill_checks_organization_id_user_id_rank_id_skill_id_index
    )
  end
end
