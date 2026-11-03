defmodule Palee.Pantheon.FitnessSettings do
  @moduledoc """
  ADR-395: a person's own settings for «Επίπεδο φυσικής κατάστασης»: the
  body weight the lifts are read against, the birth year for the age bands
  and what the card shows (`all`, `progress_only`, `none`). Account level;
  the person and their coach (an active coaching relationship) read it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @displays ~w(all progress_only none)

  @primary_key {:user_id, :binary_id, autogenerate: false}
  schema "fitness_profile_settings" do
    field :body_weight_kg, :decimal
    field :birth_year, :integer
    field :display, :string, default: "all"

    timestamps(type: :utc_datetime_usec)
  end

  def displays, do: @displays

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [:user_id, :body_weight_kg, :birth_year, :display])
    |> validate_required([:user_id, :display])
    |> validate_inclusion(:display, @displays)
    |> validate_number(:body_weight_kg, greater_than_or_equal_to: 25, less_than_or_equal_to: 300)
    |> validate_number(:birth_year, greater_than_or_equal_to: 1900)
    |> validate_birth_year()
    |> foreign_key_constraint(:user_id)
  end

  defp validate_birth_year(changeset) do
    validate_change(changeset, :birth_year, fn :birth_year, year ->
      if year > Date.utc_today().year, do: [birth_year: "is in the future"], else: []
    end)
  end
end
