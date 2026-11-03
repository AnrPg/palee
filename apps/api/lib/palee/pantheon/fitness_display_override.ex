defmodule Palee.Pantheon.FitnessDisplayOverride do
  @moduledoc """
  ADR-395: what a client's coach chose «Επίπεδο φυσικής κατάστασης» shows
  for that client in one box (`progress_only` or `none`). The client sees
  «Το όρισε ο coach σου»; no row means the client's own choice holds.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @displays ~w(progress_only none)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "fitness_display_overrides" do
    field :organization_id, :binary_id
    field :client_user_id, :binary_id
    field :display, :string
    field :set_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def displays, do: @displays

  def changeset(override \\ %__MODULE__{}, params) do
    override
    |> cast(params, [:organization_id, :client_user_id, :display, :set_by_id])
    |> validate_required([:organization_id, :client_user_id, :display])
    |> validate_inclusion(:display, @displays)
    |> unique_constraint([:organization_id, :client_user_id])
  end
end
