defmodule Palee.Nutrition.Domain.BarcodeFoodsTest do
  @moduledoc "ADR-376: barcodes, Open Food Facts products, portions, disclosure and the cache."

  use ExUnit.Case, async: true

  alias Palee.Nutrition.Domain.{Barcode, FoodCachePolicy, FoodProduct, NutrientDisclosure, PortionHint}

  describe "Barcode.parse/1" do
    test "EAN-13, EAN-8, UPC-A (as EAN-13) and GTIN-14 with a valid check digit" do
      assert {:ok, "5201054014615"} = Barcode.parse("5201054014615")
      assert {:ok, "5201054014615"} = Barcode.parse(" 5201054-014615 ")
      assert {:ok, "96385074"} = Barcode.parse("96385074")
      assert {:ok, "0036000291452"} = Barcode.parse("036000291452")
    end

    test "a misread or junk is refused" do
      for raw <- ["5201054014618", "abc", "123", "", nil, "52010540146150"] do
        assert {:error, :invalid_barcode} = Barcode.parse(raw)
      end
    end

    test "a shop's own code goes to the manual entry" do
      assert {:in_store, "2001234000000"} = Barcode.parse("2001234000000")
    end
  end

  describe "FoodProduct.from_open_food_facts/2" do
    test "keeps the name in the person's language, the first brand and per-100 g grams, never energy" do
      attrs =
        FoodProduct.from_open_food_facts(
          %{
            "product_name" => "Yoghurt",
            "product_name_el" => "Γιαούρτι",
            "brands" => "Brand A, Brand B",
            "image_front_small_url" => "https://images.example/y.jpg",
            "categories_tags" => ["en:dairies"],
            "nutriments" => %{
              "proteins_100g" => 10,
              "fat_100g" => "2.5",
              "energy-kcal_100g" => 70,
              "sugars_100g" => -1
            }
          },
          "el"
        )

      assert attrs.name == "Γιαούρτι"
      assert attrs.brand == "Brand A"
      assert attrs.nutrients == %{"proteins" => 10.0, "fat" => 2.5}
      refute Map.has_key?(attrs.nutrients, "energy-kcal")
      assert FoodProduct.from_open_food_facts(%{"brands" => "x"}) == nil
    end

    test "own nutrients are grams 0–100" do
      assert {:ok, %{"proteins" => 20.0}} = FoodProduct.cast_nutrients(%{proteins: 20})
      assert {:error, :invalid_nutrients} = FoodProduct.cast_nutrients(%{"energy" => 10})
      assert {:error, :invalid_nutrients} = FoodProduct.cast_nutrients(%{"fat" => 120})
    end
  end

  test "PortionHint suggests the hand portion" do
    assert PortionHint.hint(%{"proteins" => 10, "carbohydrates" => 3.8, "fat" => 2}) == "protein"
    assert PortionHint.hint(%{"proteins" => 12, "carbohydrates" => 71, "fat" => 1.5}) == "carbs"
    assert PortionHint.hint(%{"fat" => 91.6}) == "fat"
    assert PortionHint.hint(%{"proteins" => 5}, ["en:frozen-vegetables"]) == "veg"
    assert PortionHint.hint(%{}) == nil
    assert PortionHint.hint(%{"proteins" => 10, "carbohydrates" => 10, "fat" => 4.4}) == nil
  end

  test "NutrientDisclosure: macros only with a coach's macros and not hidden" do
    plans = [%{protein_grams: 120, carbs_grams: nil, fat_grams: nil}]
    assert NutrientDisclosure.macros_visible?(plans, false)
    refute NutrientDisclosure.macros_visible?(plans, true)
    refute NutrientDisclosure.macros_visible?([%{protein_grams: nil}], false)
    refute NutrientDisclosure.macros_visible?([], false)
    assert NutrientDisclosure.visible_nutrients(%{"fat" => 1.0}, false) == nil
  end

  describe "FoodCachePolicy" do
    @now ~U[2026-10-31 12:00:00Z]

    test "serves fresh rows, refreshes old products, retries old misses" do
      assert FoodCachePolicy.decide(nil, @now) == :lookup
      assert FoodCachePolicy.decide(%{status: "found", fetched_at: ~U[2026-10-20 12:00:00Z]}, @now) == :serve

      assert FoodCachePolicy.decide(%{status: "found", fetched_at: ~U[2026-09-01 12:00:00Z]}, @now) ==
               {:serve, :refresh}

      assert FoodCachePolicy.decide(%{status: "not_found", fetched_at: ~U[2026-10-30 12:00:00Z]}, @now) == :serve
      assert FoodCachePolicy.decide(%{status: "not_found", fetched_at: ~U[2026-10-01 12:00:00Z]}, @now) == :lookup
      assert FoodCachePolicy.decide(%{status: "pending"}, @now) == :wait
    end

    test "backs off on failures, then gives up; a found product stays found" do
      row = %{attempts: 1, name: nil}

      assert %{status: "pending", next_attempt_at: next} =
               FoodCachePolicy.after_lookup({:error, {:transient, :x}}, row, @now)

      assert DateTime.diff(next, @now) == 60
      assert %{status: "failed"} = FoodCachePolicy.after_lookup({:error, :x}, %{row | attempts: 6}, @now)
      assert %{status: "found"} = FoodCachePolicy.after_lookup({:error, :x}, %{attempts: 6, name: "Y"}, @now)
      assert %{status: "not_found", attempts: 0} = FoodCachePolicy.after_lookup({:error, :not_found}, row, @now)
      assert %{status: "found", name: "Y"} = FoodCachePolicy.after_lookup({:ok, %{name: "Y"}}, row, @now)
    end

    test "attribution names the source and its licence" do
      assert %{licence: "ODbL-1.0", url: "https://world.openfoodfacts.org/product/123"} =
               FoodCachePolicy.attribution("123")
    end
  end
end
