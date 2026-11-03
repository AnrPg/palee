defmodule Palee.Nutrition.FoodDatabase do
  @moduledoc "Dispatches the food database port to the configured adapter (ADR-376)."

  @behaviour Palee.Nutrition.Ports.FoodDatabase

  @impl true
  def lookup(barcode, language), do: adapter().lookup(barcode, language)

  defp adapter, do: Application.fetch_env!(:palee, :food_database)
end
