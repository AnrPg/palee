defmodule Palee.Infrastructure.Nutrition.UsdaFoodDataCentralClientTest do
  @moduledoc "ADR-421: the USDA FoodData Central adapter against a Req.Test plug."

  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Nutrition.UsdaFoodDataCentralClient

  @upc_as_ean "0036000291452"

  test "searches Branded Foods with the key and takes only the same GTIN" do
    Req.Test.stub(Palee.UsdaFoodDataCentral, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/fdc/v1/foods/search"
      assert conn.query_string =~ "api_key=test-usda-key"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"query" => @upc_as_ean, "dataType" => ["Branded"]} = Jason.decode!(body)

      Req.Test.json(conn, %{
        "foods" => [
          %{"gtinUpc" => "036000291453", "description" => "OTHER"},
          %{
            "gtinUpc" => "036000291452",
            "description" => "TISSUES? NO, OATS",
            "brandOwner" => "Owner",
            "foodNutrients" => [%{"nutrientNumber" => "203", "value" => 13.2}]
          }
        ]
      })
    end)

    assert {:ok, %{source: "usda_fdc", name: "TISSUES? NO, OATS", brand: "Owner"} = attrs} =
             UsdaFoodDataCentralClient.lookup(@upc_as_ean, "el")

    assert attrs.nutrients == %{"proteins" => 13.2}
  end

  test "no match, an error, and no key at all" do
    Req.Test.stub(Palee.UsdaFoodDataCentral, &Req.Test.json(&1, %{"foods" => []}))
    assert {:error, :not_found} = UsdaFoodDataCentralClient.lookup(@upc_as_ean, "el")

    Req.Test.stub(Palee.UsdaFoodDataCentral, &Plug.Conn.send_resp(&1, 429, "slow down"))

    assert {:error, {:transient, {:http, 429}}} =
             UsdaFoodDataCentralClient.lookup(@upc_as_ean, "el")

    config = Application.get_env(:palee, :usda_food_data_central)
    Application.put_env(:palee, :usda_food_data_central, Keyword.put(config, :api_key, nil))
    on_exit(fn -> Application.put_env(:palee, :usda_food_data_central, config) end)

    assert {:error, :not_configured} = UsdaFoodDataCentralClient.lookup(@upc_as_ean, "el")
  end
end
