defmodule Palee.Nutrition.CustomFood do
  @moduledoc """
  «Δικό μου τρόφιμο» (ADR-376): a food the person wrote down themselves,
  with or without a barcode (the manual fallback when a scan finds
  nothing). Theirs only; a product with a barcode reaches other members and
  Open Food Facts only when the person explicitly shares it (`shared_at`,
  ADR-421 addendum), and then without anything about them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "custom_foods" do
    field(:user_id, :binary_id)
    field(:barcode, :string)
    field(:name, :string)
    field(:brand, :string)
    field(:serving_label, :string)
    field(:portion_hint, :string)
    field(:nutrients, :map, default: %{})
    field(:note, :string)
    field(:shared_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(barcode name brand serving_label portion_hint nutrients note)a

  def changeset(food \\ %__MODULE__{}, attrs) do
    food
    |> cast(attrs, [:user_id, :shared_at | @fields])
    |> validate_required([:user_id, :name])
    |> update_change(:name, &String.trim/1)
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:brand, max: 120)
    |> validate_length(:serving_label, max: 60)
    |> validate_length(:note, max: 280)
    |> validate_format(:barcode, ~r/^[0-9]{8,14}$/)
    |> validate_inclusion(:portion_hint, ~w(protein carbs veg fat))
    |> unique_constraint([:user_id, :barcode], name: :custom_foods_user_id_barcode_index)
    |> check_constraint(:barcode, name: :custom_foods_check)
  end
end
