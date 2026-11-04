defmodule Palee.Nutrition.Domain.PortionHint do
  @moduledoc """
  The hand portion a scanned food mostly counts as (ADR-376): «παλάμη»
  protein, «χούφτα» carbohydrates, «γροθιά» vegetables or «αντίχειρας»
  fat, the same portions a meal records (ADR-159). This is how a barcode
  helps without counting anything: the member taps the suggested portion.

  Vegetables and fruit by category; otherwise the macronutrient giving the
  largest share of the food's energy (4, 4 and 9 kcal per gram; worked out
  here only and never shown), when it gives at least 40 % of it. Nil when
  nothing stands out (a mixed dish) or nothing is known.
  """

  @veg_categories ~w(en:vegetables en:fresh-vegetables en:frozen-vegetables en:salads en:legumes
                     en:fruits en:fresh-fruits)

  def hint(nutrients, categories \\ []) do
    if Enum.any?(List.wrap(categories), &(&1 in @veg_categories)) do
      "veg"
    else
      by_energy(nutrients || %{})
    end
  end

  defp by_energy(nutrients) do
    shares = %{
      "protein" => grams(nutrients, "proteins") * 4,
      "carbs" => grams(nutrients, "carbohydrates") * 4,
      "fat" => grams(nutrients, "fat") * 9
    }

    total = shares |> Map.values() |> Enum.sum()

    if total > 0 do
      {key, energy} = Enum.max_by(shares, &elem(&1, 1))
      if energy / total >= 0.4, do: key
    end
  end

  defp grams(nutrients, key) do
    case Map.get(nutrients, key) do
      value when is_number(value) -> value
      _other -> 0
    end
  end
end
