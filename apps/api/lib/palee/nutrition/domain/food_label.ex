defmodule Palee.Nutrition.Domain.FoodLabel do
  @moduledoc """
  What a label photo may prefill in «Δικό μου τρόφιμο» (ADR-421), from the
  model's reading: name, brand, portion and, per 100 g, protein,
  carbohydrates, fat, fibre, sugars and salt. Energy is never taken (vision
  §8.6). A value missing per 100 g is worked out from the per-portion column
  when the portion's grams (or ml) are known. Anything that is not a number
  from 0 to 100 g per 100 g is dropped, never guessed. The member checks and
  edits all of it before saving.
  """

  @nutrients ~w(proteins carbohydrates fat fiber sugars salt)

  @doc "`{:ok, prefill}` or `{:error, :label_unreadable}` when neither a name nor a number was read."
  def prefill(reading) when is_map(reading) do
    portion_grams = number(Map.get(reading, "serving_grams"))
    per_100g = Map.get(reading, "per_100g") || %{}
    per_serving = Map.get(reading, "per_serving") || %{}

    nutrients =
      @nutrients
      |> Enum.flat_map(fn key ->
        case per_100(number(value(per_100g, key)), number(value(per_serving, key)), portion_grams) do
          nil -> []
          grams -> [{key, grams}]
        end
      end)
      |> Map.new()

    prefill = %{
      name: text(Map.get(reading, "name"), 120),
      brand: text(Map.get(reading, "brand"), 120),
      serving_label: text(Map.get(reading, "serving_label"), 60),
      nutrients: nutrients
    }

    if is_nil(prefill.name) and nutrients == %{},
      do: {:error, :label_unreadable},
      else: {:ok, prefill}
  end

  def prefill(_reading), do: {:error, :label_unreadable}

  def nutrient_keys, do: @nutrients

  defp value(map, key) when is_map(map), do: Map.get(map, key)
  defp value(_map, _key), do: nil

  defp per_100(grams, _serving, _portion) when is_number(grams), do: checked(grams)

  defp per_100(nil, serving, portion)
       when is_number(serving) and is_number(portion) and portion > 0,
       do: checked(serving * 100 / portion)

  defp per_100(_grams, _serving, _portion), do: nil

  defp checked(grams) when grams >= 0 and grams <= 100, do: Float.round(grams * 1.0, 1)
  defp checked(_grams), do: nil

  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case value |> String.replace(",", ".") |> String.trim() |> Float.parse() do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp number(_value), do: nil

  defp text(value, max) when is_binary(value) do
    case value |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, max)
    end
  end

  defp text(_value, _max), do: nil
end
