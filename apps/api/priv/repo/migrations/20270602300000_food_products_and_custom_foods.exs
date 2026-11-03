defmodule Palee.Repo.Migrations.FoodProductsAndCustomFoods do
  @moduledoc """
  ADR-376 (CP-D9, «Σάρωση barcode»):

    * `food_products` – the platform's cache of Open Food Facts products
      (ODbL 1.0), one row per barcode, also the outbox of lookups still to
      do (`pending`, claimed with `FOR UPDATE SKIP LOCKED`). No personal
      data and no tenant: who scanned what is never stored here.
    * `custom_foods` – a person's own foods («Δικό μου τρόφιμο»), with or
      without a barcode; never contributed back to Open Food Facts.
  """

  use Ecto.Migration

  def up do
    create table(:food_products, primary_key: false) do
      add :barcode, :string, size: 14, primary_key: true
      add :status, :string, size: 16, null: false, default: "pending"
      add :source, :string, size: 32, null: false, default: "open_food_facts"
      add :name, :string, size: 200
      add :brand, :string, size: 200
      add :quantity, :string, size: 60
      add :serving_size, :string, size: 60
      add :image_url, :string, size: 500
      add :categories, {:array, :string}, null: false, default: []
      add :nutrients, :map, null: false, default: %{}
      add :portion_hint, :string, size: 16
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :claimed_at, :utc_datetime_usec
      add :fetched_at, :utc_datetime_usec
      add :last_error, :string, size: 200
      timestamps(type: :utc_datetime_usec)
    end

    create index(:food_products, [:next_attempt_at],
             where: "status = 'pending'",
             name: :food_products_due_index
           )

    create constraint(:food_products, :food_products_check,
             check: """
             status IN ('pending', 'found', 'not_found', 'failed')
             AND barcode ~ '^[0-9]{8,14}$' AND attempts >= 0
             AND (portion_hint IS NULL OR portion_hint IN ('protein', 'carbs', 'veg', 'fat'))
             AND (status <> 'found' OR name IS NOT NULL)
             """
           )

    create table(:custom_foods, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :barcode, :string, size: 14
      add :name, :string, size: 120, null: false
      add :brand, :string, size: 120
      add :serving_label, :string, size: 60
      add :portion_hint, :string, size: 16
      add :nutrients, :map, null: false, default: %{}
      add :note, :string, size: 280
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:custom_foods, [:user_id, :barcode], where: "barcode IS NOT NULL")
    create index(:custom_foods, [:user_id, :name])

    create constraint(:custom_foods, :custom_foods_check,
             check: """
             (barcode IS NULL OR barcode ~ '^[0-9]{8,14}$')
             AND (portion_hint IS NULL OR portion_hint IN ('protein', 'carbs', 'veg', 'fat'))
             """
           )

    execute("""
    CREATE POLICY custom_foods_owner_policy ON custom_foods
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE custom_foods ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE custom_foods FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:custom_foods)
    drop table(:food_products)
  end
end
