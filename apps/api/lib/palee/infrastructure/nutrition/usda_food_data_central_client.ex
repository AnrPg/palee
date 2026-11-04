defmodule Palee.Infrastructure.Nutrition.UsdaFoodDataCentralClient do
  @moduledoc """
  USDA FoodData Central, Branded Foods (https://fdc.nal.usda.gov), a food
  database port adapter (ADR-421). Public domain (CC0 1.0); USDA asks to be
  credited. A free api.data.gov key (`USDA_FDC_API_KEY`) is needed: without
  one the source answers `{:error, :not_configured}` and the chain skips it.
  1,000 requests an hour per key/IP; over it, HTTP 429 for an hour.

  Branded Foods are searched for the barcode (`POST /v1/foods/search`,
  `dataType: Branded`) and only an item whose `gtinUpc` is the same GTIN
  (leading zeros ignored: USDA keeps UPC-A as 12 digits) is taken.

  Config (`:usda_food_data_central`): `base_url`, `api_key`,
  `receive_timeout`, `req_options` (tests pass a `Req.Test` plug).
  """

  @behaviour Palee.Nutrition.Ports.FoodDatabase

  alias Palee.Nutrition.Domain.FoodProduct

  @impl true
  def lookup(barcode, _language) do
    config = Application.get_env(:palee, :usda_food_data_central, [])

    case Keyword.get(config, :api_key) do
      key when is_binary(key) and key != "" -> request(barcode, key, config)
      _missing -> {:error, :not_configured}
    end
  end

  defp request(barcode, key, config) do
    [
      method: :post,
      url: "#{Keyword.fetch!(config, :base_url)}/v1/foods/search",
      params: [api_key: key],
      json: %{query: barcode, dataType: ["Branded"], pageSize: 10},
      receive_timeout: Keyword.get(config, :receive_timeout, 3_000),
      retry: false
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
    |> interpret(barcode)
  end

  defp interpret({:ok, %Req.Response{status: 200, body: %{"foods" => foods}}}, barcode)
       when is_list(foods) do
    wanted = gtin(barcode)

    with %{} = item <- Enum.find(foods, &(is_map(&1) and gtin(Map.get(&1, "gtinUpc")) == wanted)),
         %{} = attrs <- FoodProduct.from_usda(item) do
      {:ok, Map.put(attrs, :source, "usda_fdc")}
    else
      _none -> {:error, :not_found}
    end
  end

  defp interpret({:ok, %Req.Response{status: 200}}, _barcode),
    do: {:error, {:transient, :unexpected_body}}

  defp interpret({:ok, %Req.Response{status: status}}, _barcode),
    do: {:error, {:transient, {:http, status}}}

  defp interpret({:error, exception}, _barcode),
    do: {:error, {:transient, Exception.message(exception)}}

  defp gtin(code) when is_binary(code) do
    case code |> String.trim() |> String.trim_leading("0") do
      "" -> nil
      digits -> digits
    end
  end

  defp gtin(_code), do: nil
end
