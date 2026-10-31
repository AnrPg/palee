defmodule Palee.Nutrition.CachedFood do
  @moduledoc "A barcode in the Open Food Facts cache and lookup outbox (ADR-376)."

  use Ecto.Schema

  @primary_key {:barcode, :string, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "food_products" do
    field(:status, :string, default: "pending")
    field(:source, :string, default: "open_food_facts")
    field(:name, :string)
    field(:brand, :string)
    field(:quantity, :string)
    field(:serving_size, :string)
    field(:image_url, :string)
    field(:categories, {:array, :string}, default: [])
    field(:nutrients, :map, default: %{})
    field(:portion_hint, :string)
    field(:attempts, :integer, default: 0)
    field(:next_attempt_at, :utc_datetime_usec)
    field(:claimed_at, :utc_datetime_usec)
    field(:fetched_at, :utc_datetime_usec)
    field(:last_error, :string)

    timestamps(type: :utc_datetime_usec)
  end
end
