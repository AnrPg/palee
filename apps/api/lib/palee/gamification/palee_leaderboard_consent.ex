defmodule Palee.Gamification.PaleeLeaderboardConsent do
  @moduledoc """
  ADR-394: a person's own answer to «Να μπει το σκορ σου στον πίνακα όλου
  του Palee;» — `share` or `see_only`. Account level, only its owner reads
  or writes it; withdrawing deletes the row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @choices ~w(share see_only)

  @primary_key {:user_id, :binary_id, autogenerate: false}
  schema "palee_leaderboard_consents" do
    field :choice, :string

    timestamps(type: :utc_datetime_usec)
  end

  def choices, do: @choices

  def changeset(consent \\ %__MODULE__{}, params) do
    consent
    |> cast(params, [:user_id, :choice])
    |> validate_required([:user_id, :choice])
    |> validate_inclusion(:choice, @choices)
    |> foreign_key_constraint(:user_id)
  end
end
