defmodule Palee.Nutrition.FoodLabelReader do
  @moduledoc "Dispatches the food label reader port to the configured adapter (ADR-421)."

  @behaviour Palee.Nutrition.Ports.FoodLabelReader

  @impl true
  def available?, do: adapter().available?()

  @impl true
  def read(images, options, metering), do: adapter().read(images, options, metering)

  defp adapter, do: Application.fetch_env!(:palee, :food_label_reader)
end
