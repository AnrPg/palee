defmodule Palee.Nutrition.Domain.NutrientDisclosure do
  @moduledoc """
  What a member sees of a food's numbers (ADR-376, vision §4.10 and §8.6
  «do no harm»): never energy (Palee keeps none); grams of protein,
  carbohydrates and fat only when a coach's plan of theirs sets macros and
  they have not hidden macros (`hide_macros`). Otherwise the food is its
  name, brand, picture and suggested hand portion.
  """

  @doc "Whether macros are shown: `plans` are the member's own plans."
  def macros_visible?(plans, hide_macros?) do
    not hide_macros? and
      Enum.any?(plans, fn plan ->
        Enum.any?([:protein_grams, :carbs_grams, :fat_grams], &is_integer(Map.get(plan, &1)))
      end)
  end

  @doc "The nutrients to send: all kept ones when visible, none otherwise."
  def visible_nutrients(_nutrients, false), do: nil
  def visible_nutrients(nutrients, true), do: nutrients || %{}
end
