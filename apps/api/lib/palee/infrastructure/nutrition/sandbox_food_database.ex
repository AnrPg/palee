defmodule Palee.Infrastructure.Nutrition.SandboxFoodDatabase do
  @moduledoc """
  The food database in dev and tests (ADR-376): a few fixed products and
  fixed answers, no network.

    * `5201054014615` – Greek yoghurt 2% (protein);
    * `5200101800133` – pasta (carbohydrates);
    * `5201671800028` – extra virgin olive oil (fat);
    * `8001505005707` – frozen peas (vegetables);
    * any other code – not in the database (e.g. `5201234500006`);
    * `9990000000012` – the database is down (transient).
  """

  @behaviour Palee.Nutrition.Ports.FoodDatabase

  alias Palee.Nutrition.Domain.FoodProduct

  @products %{
    "5201054014615" => %{
      "product_name_el" => "Γιαούρτι στραγγιστό 2%",
      "product_name" => "Greek yoghurt 2%",
      "brands" => "Sandbox Dairy",
      "quantity" => "1 kg",
      "serving_size" => "170 g",
      "categories_tags" => ["en:dairies", "en:yogurts"],
      "nutriments" => %{"proteins_100g" => 10, "carbohydrates_100g" => 3.8, "fat_100g" => 2}
    },
    "5200101800133" => %{
      "product_name" => "Spaghetti No 10",
      "brands" => "Sandbox Pasta",
      "quantity" => "500 g",
      "categories_tags" => ["en:pastas"],
      "nutriments" => %{"proteins_100g" => 12, "carbohydrates_100g" => 71, "fat_100g" => 1.5}
    },
    "5201671800028" => %{
      "product_name_el" => "Εξαιρετικό παρθένο ελαιόλαδο",
      "brands" => "Sandbox Olive",
      "quantity" => "1 l",
      "categories_tags" => ["en:olive-oils"],
      "nutriments" => %{"proteins_100g" => 0, "carbohydrates_100g" => 0, "fat_100g" => 91.6}
    },
    "8001505005707" => %{
      "product_name" => "Frozen peas",
      "brands" => "Sandbox Frozen",
      "quantity" => "450 g",
      "categories_tags" => ["en:frozen-vegetables"],
      "nutriments" => %{"proteins_100g" => 5, "carbohydrates_100g" => 9, "fat_100g" => 0.4}
    }
  }

  @impl true
  def lookup("9990000000012", _language), do: {:error, {:transient, :sandbox_down}}

  def lookup(barcode, language) do
    case Map.fetch(@products, barcode) do
      {:ok, product} ->
        {:ok,
         product
         |> FoodProduct.from_open_food_facts(language)
         |> Map.put(:source, "open_food_facts")}

      :error ->
        {:error, :not_found}
    end
  end
end
