defmodule Palee.Repo.Migrations.FoodProductShares do
  @moduledoc """
  ADR-421 addendum (a member shares an own food with everyone):

    * `custom_foods.shared_at` – when the person chose to share this food
      (their own row, so it travels with their data export).
    * `food_product_shares` – one row per shared barcode (the first share
      wins): what was shared (product data only: name, brand, portion,
      nutrition per 100 g), when, and who, for abuse handling only (never
      shown publicly; emptied when the account goes). It is also the outbox
      of contributions to Open Food Facts (`off_status`).
  """

  use Ecto.Migration

  def up do
    alter table(:custom_foods) do
      add :shared_at, :utc_datetime_usec
    end

    create table(:food_product_shares, primary_key: false) do
      add :barcode, :string, size: 14, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, size: 200, null: false
      add :brand, :string, size: 200
      add :serving_size, :string, size: 60
      add :portion_hint, :string, size: 16
      add :nutrients, :map, null: false, default: %{}
      add :language, :string, size: 5, null: false, default: "el"
      add :shared_at, :utc_datetime_usec, null: false
      add :off_status, :string, size: 16, null: false, default: "queued"
      add :off_attempts, :integer, null: false, default: 0
      add :off_next_attempt_at, :utc_datetime_usec
      add :off_claimed_at, :utc_datetime_usec
      add :off_sent_at, :utc_datetime_usec
      add :off_last_error, :string, size: 200
      timestamps(type: :utc_datetime_usec)
    end

    create index(:food_product_shares, [:off_next_attempt_at],
             where: "off_status = 'queued'",
             name: :food_product_shares_due_index
           )

    create index(:food_product_shares, [:user_id])

    create constraint(:food_product_shares, :food_product_shares_check,
             check: """
             barcode ~ '^[0-9]{8,14}$' AND off_attempts >= 0
             AND off_status IN ('queued', 'sent', 'exists', 'failed')
             AND (portion_hint IS NULL OR portion_hint IN ('protein', 'carbs', 'veg', 'fat'))
             """
           )
  end

  def down do
    drop table(:food_product_shares)

    alter table(:custom_foods) do
      remove :shared_at
    end
  end
end
