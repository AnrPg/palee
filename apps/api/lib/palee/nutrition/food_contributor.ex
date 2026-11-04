defmodule Palee.Nutrition.FoodContributor do
  @moduledoc "Dispatches the food contributor port to the configured adapter (ADR-421 addendum)."

  @behaviour Palee.Nutrition.Ports.FoodContributor

  @impl true
  def configured?, do: adapter().configured?()

  @impl true
  def contribute(share), do: adapter().contribute(share)

  defp adapter, do: Application.fetch_env!(:palee, :food_contributor)
end
