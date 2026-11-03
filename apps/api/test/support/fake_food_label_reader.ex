defmodule Palee.FakeFoodLabelReader do
  @moduledoc """
  Test stand-in for the label reading model (ADR-421); tells the test
  process what it was sent. `:fake_food_label_reader` in the app env:
  `:reads` (default), `:off` (not available) or `:unreadable`.
  """

  @behaviour Palee.Nutrition.Ports.FoodLabelReader

  @impl true
  def available?, do: Application.get_env(:palee, :fake_food_label_reader, :reads) != :off

  @impl true
  def read(images, %{locale: locale}, metering) do
    send(self(), {:label_read, length(images), locale, metering})

    case Application.get_env(:palee, :fake_food_label_reader, :reads) do
      :off ->
        {:error, :not_configured}

      :unreadable ->
        {:ok, %{"name" => nil, "per_100g" => %{"proteins" => nil}}}

      :reads ->
        {:ok,
         %{
           "name" => "  Φέτα ΠΟΠ ",
           "brand" => "Sandbox Dairy",
           "serving_label" => "1 φέτα (30 g)",
           "serving_grams" => 30,
           "per_100g" => %{"proteins" => 17, "fat" => "21,5", "carbohydrates" => nil},
           "per_serving" => %{"carbohydrates" => 0.3, "salt" => 0.9, "energy" => 80}
         }}
    end
  end
end
