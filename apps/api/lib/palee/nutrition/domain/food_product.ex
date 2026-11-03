defmodule Palee.Nutrition.Domain.FoodProduct do
  @moduledoc """
  What Palee keeps of an Open Food Facts product (ADR-376): its name (in
  the person's language when the product has it), brand, quantity, serving
  size, front image, categories and, per 100 g, protein, carbohydrates,
  fat, fibre, sugars and salt. Energy is never kept: Palee shows no
  calories to members (vision §8.6), so it has no reason to hold them.

  The fields are taken unmodified from the product (ODbL: a cached extract,
  not a new database), only trimmed to length.
  """

  @nutrients ~w(proteins carbohydrates fat fiber sugars salt)
  @name_languages ~w(el en)

  def nutrient_keys, do: @nutrients

  @doc "The cache attributes of an OFF product payload (`product` object), or nil without a name."
  def from_open_food_facts(product, language \\ "el") when is_map(product) do
    case name(product, language) do
      nil ->
        nil

      name ->
        %{
          name: trim(name, 200),
          brand: product |> Map.get("brands") |> first_brand() |> trim(200),
          quantity: product |> Map.get("quantity") |> trim(60),
          serving_size: product |> Map.get("serving_size") |> trim(60),
          image_url: product |> image() |> trim(500),
          categories: product |> Map.get("categories_tags", []) |> List.wrap() |> Enum.take(20),
          nutrients: nutrients(Map.get(product, "nutriments") || %{})
        }
    end
  end

  defp name(product, language) do
    [language | @name_languages]
    |> Enum.uniq()
    |> Enum.map(&Map.get(product, "product_name_" <> &1))
    |> Kernel.++([Map.get(product, "product_name"), Map.get(product, "generic_name")])
    |> Enum.find(&(is_binary(&1) and String.trim(&1) != ""))
  end

  defp image(product) do
    Map.get(product, "image_front_small_url") || Map.get(product, "image_front_url") ||
      Map.get(product, "image_url")
  end

  defp first_brand(brands) when is_binary(brands),
    do: brands |> String.split(",") |> List.first() |> String.trim()

  defp first_brand(_brands), do: nil

  defp nutrients(nutriments) do
    @nutrients
    |> Enum.flat_map(fn key ->
      case number(Map.get(nutriments, key <> "_100g")) do
        nil -> []
        value -> [{key, value}]
      end
    end)
    |> Map.new()
  end

  defp number(value) when is_integer(value) and value >= 0, do: value * 1.0
  defp number(value) when is_float(value) and value >= 0, do: Float.round(value, 2)

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} when number >= 0 -> Float.round(number, 2)
      _other -> nil
    end
  end

  defp number(_value), do: nil

  defp trim(nil, _max), do: nil
  defp trim(text, max) when is_binary(text), do: text |> String.trim() |> String.slice(0, max)
  defp trim(_value, _max), do: nil

  @doc "Validates a person's own nutrients map (same keys, 0–100 g per 100 g)."
  def cast_nutrients(nil), do: {:ok, %{}}

  def cast_nutrients(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      key = to_string(key)

      cond do
        is_nil(value) ->
          {:cont, {:ok, acc}}

        key in @nutrients and is_number(value) and value >= 0 and value <= 100 ->
          {:cont, {:ok, Map.put(acc, key, value * 1.0)}}

        true ->
          {:halt, {:error, :invalid_nutrients}}
      end
    end)
  end

  def cast_nutrients(_map), do: {:error, :invalid_nutrients}
end
