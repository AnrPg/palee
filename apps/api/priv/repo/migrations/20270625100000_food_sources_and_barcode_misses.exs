defmodule Palee.Repo.Migrations.FoodSourcesAndBarcodeMisses do
  @moduledoc """
  ADR-421 (more free sources for «Σάρωση barcode»):

    * `food_products.attribution` – the credit a row's source asks for when
      it is not one of the fixed ones (an imported product list carries its
      own name and licence). Rows still come from exactly one source.
    * `food_catalogue_products` – product lists Palee is licensed to use
      (the Greek source), imported with `mix palee.food_catalogue.import`:
      barcode, name, brand, size and the list's licence. No nutrition, no
      personal data, no tenant.
    * `food_barcode_misses` – barcodes a scan found nowhere, per country
      (the member's main «Η περιοχή μου», else empty), with a count and the
      first and last day. Never who scanned, never the time of day.
  """

  use Ecto.Migration

  def up do
    alter table(:food_products) do
      add :attribution, :map
    end

    create table(:food_catalogue_products, primary_key: false) do
      add :list, :string, size: 32, primary_key: true
      add :barcode, :string, size: 14, primary_key: true
      add :name, :string, size: 200, null: false
      add :brand, :string, size: 200
      add :quantity, :string, size: 60
      add :source_name, :string, size: 120, null: false
      add :licence, :string, size: 60, null: false
      add :licence_url, :string, size: 500
      timestamps(type: :utc_datetime_usec)
    end

    create index(:food_catalogue_products, [:barcode])

    create constraint(:food_catalogue_products, :food_catalogue_products_check,
             check: "barcode ~ '^[0-9]{8,14}$' AND list ~ '^[a-z0-9_]{2,32}$'"
           )

    create table(:food_barcode_misses, primary_key: false) do
      add :barcode, :string, size: 14, primary_key: true
      add :country, :string, size: 2, primary_key: true
      add :scans, :integer, null: false, default: 1
      add :first_seen_on, :date, null: false
      add :last_seen_on, :date, null: false
    end

    create index(:food_barcode_misses, [:scans])

    create constraint(:food_barcode_misses, :food_barcode_misses_check,
             check:
               "barcode ~ '^[0-9]{8,14}$' AND country ~ '^([A-Z]{2})?$' AND scans > 0 " <>
                 "AND last_seen_on >= first_seen_on"
           )
  end

  def down do
    drop table(:food_barcode_misses)
    drop table(:food_catalogue_products)

    alter table(:food_products) do
      remove :attribution
    end
  end
end
