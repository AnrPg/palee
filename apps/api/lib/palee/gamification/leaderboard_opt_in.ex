defmodule Palee.Gamification.LeaderboardOptIn do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "leaderboard_opt_ins" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :opted_in_at, :utc_datetime_usec
    # ADR-356 (CP-D2): optional, told by the person for fair comparisons.
    field :division, :string
    field :birth_year, :integer
  end

  def changeset(opt_in \\ %__MODULE__{}, params) do
    opt_in
    |> cast(params, [:organization_id, :user_id, :opted_in_at])
    |> validate_required([:user_id, :opted_in_at])
    |> unique_constraint([:organization_id, :user_id],
      name: :leaderboard_opt_ins_organization_user_index
    )
    |> foreign_key_constraint(:user_id)
  end

  @doc "ADR-356: the person's division and birth year (both optional)."
  def profile_changeset(%__MODULE__{} = opt_in, params) do
    opt_in
    |> cast(params, [:division, :birth_year])
    |> validate_inclusion(:division, Palee.Gamification.Domain.LeaderboardFilters.divisions())
    |> validate_number(:birth_year, greater_than_or_equal_to: 1900, less_than_or_equal_to: 2100)
    |> check_constraint(:division, name: :leaderboard_opt_ins_division_check)
  end
end
