defmodule Palee.Infrastructure.Nutrition.OpenFoodFactsClientTest do
  @moduledoc "ADR-376: the Open Food Facts adapter against a Req.Test plug."

  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Nutrition.OpenFoodFactsClient

  test "asks v2 for the product with Palee's User-Agent and reads it" do
    Req.Test.stub(Palee.OpenFoodFacts, fn conn ->
      assert conn.request_path == "/api/v2/product/5201054014615.json"
      assert [agent] = Plug.Conn.get_req_header(conn, "user-agent")
      assert agent =~ "Palee"
      assert conn.query_string =~ "fields="

      Req.Test.json(conn, %{
        "status" => 1,
        "product" => %{
          "product_name" => "Yoghurt",
          "brands" => "Brand",
          "nutriments" => %{"proteins_100g" => 10, "energy-kcal_100g" => 70}
        }
      })
    end)

    assert {:ok, %{name: "Yoghurt", nutrients: %{"proteins" => 10.0} = nutrients}} =
             OpenFoodFactsClient.lookup("5201054014615", "el")

    assert map_size(nutrients) == 1
  end

  test "an unknown product, an error and a nameless product" do
    Req.Test.stub(Palee.OpenFoodFacts, &Req.Test.json(&1, %{"status" => 0}))
    assert {:error, :not_found} = OpenFoodFactsClient.lookup("5201234500006", "el")

    Req.Test.stub(Palee.OpenFoodFacts, &Plug.Conn.send_resp(&1, 503, "busy"))
    assert {:error, {:transient, {:http, 503}}} = OpenFoodFactsClient.lookup("5201234500006", "el")

    Req.Test.stub(Palee.OpenFoodFacts, &Req.Test.json(&1, %{"status" => 1, "product" => %{}}))
    assert {:error, :not_found} = OpenFoodFactsClient.lookup("5201234500006", "el")
  end
end
