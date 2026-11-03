defmodule Palee.Infrastructure.Nutrition.OpenFoodFactsClient do
  @moduledoc """
  Open Food Facts (https://world.openfoodfacts.org), the food database port
  (ADR-376). Data under the Open Database License 1.0, images under
  CC BY-SA. Read API v2, no key; Open Food Facts asks every app to send a
  User-Agent naming it and a contact, and limits product reads to 15 a
  minute per IP (official API docs, read 2026-11-03); the 30-day cache, the
  outbox and one ask per barcode per cache period keep Palee below it.

  Config (`:open_food_facts`): `base_url`, `user_agent`, `receive_timeout`,
  `req_options` (tests pass a `Req.Test` plug).
  """

  @behaviour Palee.Nutrition.Ports.FoodDatabase

  alias Palee.Nutrition.Domain.FoodProduct

  @fields ~w(code product_name product_name_el product_name_en generic_name brands quantity
             serving_size image_front_small_url image_front_url categories_tags nutriments)

  @impl true
  def lookup(barcode, language) do
    config = Application.get_env(:palee, :open_food_facts, [])

    [
      method: :get,
      url: "#{Keyword.fetch!(config, :base_url)}/api/v2/product/#{barcode}.json",
      params: [fields: Enum.join(@fields, ",")],
      headers: [{"user-agent", Keyword.fetch!(config, :user_agent)}],
      receive_timeout: Keyword.get(config, :receive_timeout, 4_000),
      retry: false,
      decode_body: false
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
    |> interpret(language)
  end

  defp interpret({:ok, %Req.Response{status: 200, body: body}}, language) do
    case decode(body) do
      %{"status" => 1, "product" => product} when is_map(product) ->
        case FoodProduct.from_open_food_facts(product, language) do
          nil -> {:error, :not_found}
          attrs -> {:ok, Map.put(attrs, :source, "open_food_facts")}
        end

      %{"status" => 0} ->
        {:error, :not_found}

      _other ->
        {:error, {:transient, :unexpected_body}}
    end
  end

  defp interpret({:ok, %Req.Response{status: 404}}, _language), do: {:error, :not_found}

  defp interpret({:ok, %Req.Response{status: status}}, _language),
    do: {:error, {:transient, {:http, status}}}

  defp interpret({:error, exception}, _language),
    do: {:error, {:transient, Exception.message(exception)}}

  defp decode(body) when is_map(body), do: body

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _error -> %{}
    end
  end

  defp decode(_body), do: %{}
end
