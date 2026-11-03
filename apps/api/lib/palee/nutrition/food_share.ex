defmodule Palee.Nutrition.FoodShare do
  @moduledoc """
  A product a member chose to share with everyone (ADR-421 addendum): the
  first share of a barcode, what it said (product data only), when, and who
  shared it. `user_id` is for abuse handling only and is never shown or
  sent anywhere. The row is also the outbox of the contribution to Open Food
  Facts (`off_*`).
  """

  use Ecto.Schema

  @primary_key {:barcode, :string, autogenerate: false}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "food_product_shares" do
    field(:user_id, :binary_id)
    field(:name, :string)
    field(:brand, :string)
    field(:serving_size, :string)
    field(:portion_hint, :string)
    field(:nutrients, :map, default: %{})
    field(:language, :string, default: "el")
    field(:shared_at, :utc_datetime_usec)
    field(:off_status, :string, default: "queued")
    field(:off_attempts, :integer, default: 0)
    field(:off_next_attempt_at, :utc_datetime_usec)
    field(:off_claimed_at, :utc_datetime_usec)
    field(:off_sent_at, :utc_datetime_usec)
    field(:off_last_error, :string)

    timestamps(type: :utc_datetime_usec)
  end
end
