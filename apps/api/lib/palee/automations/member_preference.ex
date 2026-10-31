defmodule Palee.Automations.MemberPreference do
  @moduledoc """
  ADR-346: what a box member chose about this box's automatic messages:
  none at all (`opted_out_at`), not from some recipes, and the birthday
  (day and month, never the year) they chose to share for a greeting.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Automations.Domain.RecipeCatalog

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "automation_member_preferences" do
    field :organization_id, :binary_id, read_after_writes: true
    field :user_id, :binary_id
    field :opted_out_at, :utc_datetime_usec
    field :opted_out_recipes, {:array, :string}, default: []
    field :birthday_month, :integer
    field :birthday_day, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(preference, params) do
    preference
    |> cast(params, [:user_id, :opted_out_at, :opted_out_recipes, :birthday_month, :birthday_day])
    |> validate_required([:user_id])
    |> validate_subset(:opted_out_recipes, RecipeCatalog.keys())
    |> validate_birthday()
    |> unique_constraint([:organization_id, :user_id])
  end

  defp validate_birthday(changeset) do
    month = get_field(changeset, :birthday_month)
    day = get_field(changeset, :birthday_day)

    cond do
      is_nil(month) and is_nil(day) -> changeset
      is_nil(month) or is_nil(day) -> add_error(changeset, :birthday_day, "invalid")
      # 2000 is a leap year, so 29 February is a valid birthday.
      match?({:ok, _date}, Date.new(2000, month, day)) -> changeset
      true -> add_error(changeset, :birthday_day, "invalid")
    end
  end
end
