defmodule Palee.Nutrition.CatalogueProduct do
  @moduledoc """
  A product of a list Palee is licensed to use (ADR-421), e.g. a Greek
  product list: barcode, name, brand and size, with the list's own credit.
  No nutrition and no personal data. Imported with
  `mix palee.food_catalogue.import`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  @type t :: %__MODULE__{}

  schema "food_catalogue_products" do
    field(:list, :string, primary_key: true)
    field(:barcode, :string, primary_key: true)
    field(:name, :string)
    field(:brand, :string)
    field(:quantity, :string)
    field(:source_name, :string)
    field(:licence, :string)
    field(:licence_url, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(list barcode name brand quantity source_name licence licence_url)a

  def changeset(product \\ %__MODULE__{}, attrs) do
    product
    |> cast(attrs, @fields)
    |> validate_required([:list, :barcode, :name, :source_name, :licence])
    |> validate_format(:list, ~r/^[a-z0-9_]{2,32}$/)
    |> validate_format(:barcode, ~r/^[0-9]{8,14}$/)
    |> validate_length(:name, max: 200)
    |> validate_length(:brand, max: 200)
    |> validate_length(:quantity, max: 60)
    |> validate_length(:source_name, max: 120)
    |> validate_length(:licence, max: 60)
    |> validate_length(:licence_url, max: 500)
  end
end
