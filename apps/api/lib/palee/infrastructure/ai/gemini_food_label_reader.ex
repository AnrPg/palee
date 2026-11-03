defmodule Palee.Infrastructure.Ai.GeminiFoodLabelReader do
  @moduledoc """
  Reads a food label from one or two photos with Gemini (ADR-421), through
  the platform's vision call (ADR-157, `GEMINI_VISION_MODEL`, metered per
  ADR-152). The answer is JSON: name, brand, portion and the nutrition table
  per 100 g and per portion, without energy. Only the photos and this fixed
  instruction are sent; the photos are not kept.
  """

  @behaviour Palee.Nutrition.Ports.FoodLabelReader

  alias Palee.Infrastructure.Ai.GeminiVision

  @nutrient_fields ~s("proteins", "carbohydrates", "fat", "fiber", "sugars", "salt")

  @instructions """
  You read the packaging of one food product from photos: its front and its
  nutrition table. Reply with one JSON object only, with these keys:
  "name" (the product name as printed, in the label's own language),
  "brand", "serving_label" (the portion as printed, e.g. "1 cup (30 g)"),
  "serving_grams" (that portion in grams or millilitres, a number),
  "per_100g" and "per_serving", each an object with the keys
  #{@nutrient_fields} in grams (numbers).
  Use null for anything not printed or not readable. Never estimate or
  calculate a value that is not printed. Do not include energy, kJ or kcal.
  """

  @impl true
  def available?, do: GeminiVision.configured?()

  @impl true
  def read(images, %{locale: _locale}, metering) do
    case GeminiVision.generate(
           images,
           @instructions,
           "Read this product's label.",
           %{temperature: 0, maxOutputTokens: 500, responseMimeType: "application/json"},
           metering,
           "food_label"
         ) do
      {:ok, {:blocked, _reason}} -> {:error, :blocked}
      {:ok, text} when is_binary(text) -> decode(text)
      other -> other
    end
  end

  defp decode(text) do
    text = text |> String.trim() |> String.trim_leading("```json") |> String.trim("`")

    case Jason.decode(text) do
      {:ok, %{} = reading} -> {:ok, reading}
      _other -> {:error, :unreadable_answer}
    end
  end
end
