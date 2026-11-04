defmodule Palee.Infrastructure.Nutrition.ChainFoodDatabaseTest do
  @moduledoc """
  ADR-421: the chain asks Open Food Facts, USDA and the licensed lists in
  order, each with its own timeout inside a total budget.
  """

  use Palee.DataCase, async: false

  alias Palee.Infrastructure.Nutrition.{
    ChainFoodDatabase,
    EctoFoodCatalogue,
    OpenFoodFactsClient,
    UsdaFoodDataCentralClient
  }

  @code "5201234500006"

  defmodule Slow do
    @moduledoc false
    def lookup(_barcode, _language) do
      Process.sleep(500)
      {:ok, %{name: "too late", source: "slow"}}
    end
  end

  defmodule Boom do
    @moduledoc false
    def lookup(_barcode, _language), do: raise("boom")
  end

  @sources [
    {OpenFoodFactsClient, 1_000},
    {UsdaFoodDataCentralClient, 1_000},
    {EctoFoodCatalogue, 1_000}
  ]

  defp chain(sources \\ @sources, budget \\ 3_000),
    do: ChainFoodDatabase.lookup(@code, "el", sources: sources, total_timeout_ms: budget)

  defp off(answer), do: Req.Test.stub(Palee.OpenFoodFacts, answer)
  defp usda(answer), do: Req.Test.stub(Palee.UsdaFoodDataCentral, answer)
  defp off_missing, do: off(&Req.Test.json(&1, %{"status" => 0}))
  defp usda_missing, do: usda(&Req.Test.json(&1, %{"foods" => []}))

  test "the first source that has it wins; later ones are not asked" do
    off(
      &Req.Test.json(&1, %{
        "status" => 1,
        "product" => %{"product_name" => "Off product", "nutriments" => %{}}
      })
    )

    usda(fn _conn -> flunk("USDA must not be asked") end)

    assert {:ok, %{source: "open_food_facts", name: "Off product"}} = chain()
  end

  test "not in Open Food Facts: USDA, then the licensed list" do
    off_missing()

    usda(
      &Req.Test.json(&1, %{
        "foods" => [%{"gtinUpc" => @code, "description" => "US product", "foodNutrients" => []}]
      })
    )

    assert {:ok, %{source: "usda_fdc", name: "US product"}} = chain()

    usda_missing()

    {:ok, 1} =
      EctoFoodCatalogue.import_list(
        [
          %{
            list: "gr_test",
            barcode: @code,
            name: "Ελληνικό προϊόν",
            brand: "Μάρκα",
            quantity: "500 g",
            source_name: "Λίστα δοκιμής",
            licence: "CC BY 4.0"
          }
        ],
        DateTime.utc_now()
      )

    assert {:ok,
            %{
              source: "catalogue",
              name: "Ελληνικό προϊόν",
              nutrients: %{},
              attribution: %{"source" => "Λίστα δοκιμής", "licence" => "CC BY 4.0"}
            }} = chain()
  end

  test "nobody has it: not found; a failure anywhere means try again later" do
    off_missing()
    usda_missing()
    assert {:error, :not_found} = chain()

    off(&Plug.Conn.send_resp(&1, 503, "busy"))
    assert {:error, {:transient, {:sources, [{"OpenFoodFactsClient", _}]}}} = chain()
  end

  test "a slow or crashing source is cut off and the next one is asked" do
    usda_missing()

    assert {:error, {:transient, {:sources, [{"Slow", :timeout}, {"Boom", {:crashed, "boom"}}]}}} =
             chain([{Slow, 50}, {Boom, 50}, {UsdaFoodDataCentralClient, 1_000}])

    usda(
      &Req.Test.json(&1, %{"foods" => [%{"gtinUpc" => @code, "description" => "Found after"}]})
    )

    assert {:ok, %{name: "Found after"}} = chain([{Slow, 50}, {UsdaFoodDataCentralClient, 1_000}])
  end

  test "the total budget stops the chain" do
    started = System.monotonic_time(:millisecond)

    assert {:error, {:transient, {:sources, [{"Slow", :timeout}, {"Slow", :budget}]}}} =
             chain([{Slow, 1_000}, {Slow, 1_000}], 100)

    assert System.monotonic_time(:millisecond) - started < 400
  end

  test "a source switched off is skipped" do
    config = Application.get_env(:palee, :usda_food_data_central)
    Application.put_env(:palee, :usda_food_data_central, Keyword.put(config, :api_key, ""))
    on_exit(fn -> Application.put_env(:palee, :usda_food_data_central, config) end)

    off_missing()
    usda(fn _conn -> flunk("no key, no call") end)
    assert {:error, :not_found} = chain()
  end
end
