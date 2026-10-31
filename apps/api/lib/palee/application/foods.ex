defmodule Palee.Application.Foods do
  @moduledoc """
  «Σάρωση barcode» in meals and «Δικά μου τρόφιμα» (ADR-376, CP-D9).

  A scan looks first at the person's own foods, then at the cached Open
  Food Facts product, and asks Open Food Facts only on a miss (once, with
  a short timeout; a slow or failed call is left to the outbox worker and
  the answer is `pending`). A product nobody knows, or a shop's own code,
  ends in the manual entry, which saves a custom food with that barcode.

  What the person sees follows `NutrientDisclosure`: never energy, macros
  only with a coach's plan that sets them and `hide_macros` off. The
  feature is optional and only offered where meals are (vision §4.10).
  Who scanned what is never stored.
  """

  alias Palee.Application.Clock
  alias Palee.{Nutrition, Wellness}
  alias Palee.Nutrition.{FoodDatabase, FoodStore}

  @default_language "el"

  def barcode(%{user_id: user_id} = context, raw, language \\ @default_language) do
    case Nutrition.parse_barcode(raw) do
      {:error, reason} ->
        {:error, reason}

      {:in_store, code} ->
        {:ok, result(code, "manual", nil, nil, false) |> Map.put(:reason, "in_store_code")}

      {:ok, code} ->
        visible? = macros_visible?(context, user_id)

        case FoodStore.with_context(context, fn ->
               FoodStore.custom_food_by_barcode(user_id, code)
             end) do
          %{} = food ->
            {:ok, result(code, "found", "custom", present_custom(food, visible?), visible?)}

          nil ->
            {:ok, from_cache(code, language, visible?)}
        end
    end
  end

  defp from_cache(code, language, visible?) do
    now = Clock.now()
    row = FoodStore.get_cached(code)

    case Nutrition.food_cache_decision(row, now) do
      :serve ->
        present_cached(row, visible?)

      {:serve, :refresh} ->
        :ok = FoodStore.request_lookup(code, now)
        present_cached(row, visible?)

      :wait ->
        code |> lookup_now(language, now) |> present_cached(visible?)

      :lookup ->
        :ok = FoodStore.request_lookup(code, now)
        code |> lookup_now(language, now) |> present_cached(visible?)
    end
  end

  # One inline attempt when this request can claim the row; another request
  # already asking means `pending`.
  defp lookup_now(code, language, now) do
    case FoodStore.claim(code, now, 1) do
      [row] -> run_lookup(row, language, now)
      [] -> FoodStore.get_cached(code)
    end
  end

  @doc "The outbox worker: looks up due barcodes. Returns how many were handled."
  def process_due(limit \\ 20) do
    now = Clock.now()
    rows = FoodStore.claim(:due, now, limit)
    Enum.each(rows, &run_lookup(&1, @default_language, now))
    {:ok, length(rows)}
  end

  defp run_lookup(row, language, now) do
    outcome =
      case FoodDatabase.lookup(row.barcode, language) do
        {:ok, attrs} ->
          {:ok,
           Map.put(
             attrs,
             :portion_hint,
             Nutrition.portion_hint(attrs.nutrients, attrs.categories)
           )}

        other ->
          other
      end

    {:ok, saved} =
      FoodStore.finish(row.barcode, Nutrition.food_after_lookup(outcome, row, now), now)

    saved
  end

  defp present_cached(%{status: "found"} = row, visible?) do
    food = %{
      id: nil,
      name: row.name,
      brand: row.brand,
      quantity: row.quantity,
      serving_size: row.serving_size,
      image_url: row.image_url,
      portion_hint: row.portion_hint,
      nutrients: Nutrition.visible_nutrients(row.nutrients, visible?)
    }

    row.barcode
    |> result("found", "open_food_facts", food, visible?)
    |> Map.put(:attribution, Nutrition.food_attribution(row.barcode))
  end

  defp present_cached(%{status: status} = row, visible?) when status in ~w(not_found failed),
    do: result(row.barcode, "manual", nil, nil, visible?) |> Map.put(:reason, status)

  defp present_cached(%{barcode: code}, visible?), do: result(code, "pending", nil, nil, visible?)

  defp result(code, status, source, food, visible?) do
    %{
      barcode: code,
      status: status,
      source: source,
      food: food,
      macros_visible: visible?,
      attribution: nil,
      reason: nil
    }
  end

  # Custom foods ------------------------------------------------------------

  def list(%{user_id: user_id} = context) do
    visible? = macros_visible?(context, user_id)

    foods =
      FoodStore.with_context(context, fn -> FoodStore.list_custom_foods(user_id) end)
      |> Enum.map(&present_custom(&1, visible?))

    {:ok, %{foods: foods, macros_visible: visible?}}
  end

  def create(%{user_id: user_id} = context, params) do
    with {:ok, attrs} <- custom_attrs(params) do
      FoodStore.with_context(context, fn ->
        case FoodStore.insert_custom_food(Map.put(attrs, :user_id, user_id)) do
          {:ok, food} -> {:ok, present_custom(food, macros_visible?(context, user_id))}
          error -> error
        end
      end)
    end
  end

  def update(%{user_id: user_id} = context, id, params) do
    with {:ok, attrs} <- custom_attrs(params) do
      FoodStore.with_context(context, fn ->
        with %{} = food <- FoodStore.get_custom_food(id, user_id) || {:error, :not_found},
             {:ok, food} <- FoodStore.update_custom_food(food, attrs) do
          {:ok, present_custom(food, macros_visible?(context, user_id))}
        end
      end)
    end
  end

  def delete(%{user_id: user_id} = context, id) do
    FoodStore.with_context(context, fn ->
      case FoodStore.get_custom_food(id, user_id) do
        nil -> {:error, :not_found}
        food -> FoodStore.delete_custom_food(food)
      end
    end)
  end

  defp custom_attrs(params) do
    given = params_map(params)

    with {:ok, code} <- custom_barcode(given["barcode"]),
         {:ok, nutrients} <- Nutrition.cast_food_nutrients(given["nutrients"]) do
      attrs =
        for key <- ~w(name brand serving_label note portion_hint barcode nutrients),
            Map.has_key?(given, key),
            into: %{} do
          case key do
            "barcode" -> {:barcode, code}
            "nutrients" -> {:nutrients, nutrients}
            other -> {String.to_existing_atom(other), given[other]}
          end
        end

      if Map.has_key?(given, "nutrients") and not Map.has_key?(given, "portion_hint"),
        do: {:ok, Map.put(attrs, :portion_hint, Nutrition.portion_hint(nutrients, []))},
        else: {:ok, attrs}
    end
  end

  defp custom_barcode(nil), do: {:ok, nil}

  defp custom_barcode(raw) do
    case Nutrition.parse_barcode(raw) do
      {:ok, code} -> {:ok, code}
      {:in_store, code} -> {:ok, code}
      error -> error
    end
  end

  # The person's own food shows its own numbers only where macros may show.
  defp present_custom(food, visible?) do
    %{
      id: food.id,
      barcode: food.barcode,
      name: food.name,
      brand: food.brand,
      quantity: nil,
      serving_size: food.serving_label,
      image_url: nil,
      portion_hint: food.portion_hint,
      note: food.note,
      nutrients: Nutrition.visible_nutrients(food.nutrients, visible?)
    }
  end

  defp macros_visible?(context, user_id) do
    plans = Nutrition.list_own_plans(context)
    prefs = Wellness.with_context(context, fn -> Wellness.preferences(user_id) end)
    Nutrition.macros_visible?(plans, prefs.hide_macros == true)
  end

  defp params_map(params) when is_struct(params), do: params |> Map.from_struct() |> params_map()

  defp params_map(params) when is_map(params),
    do: Map.new(params, fn {k, v} -> {to_string(k), v} end)

  defp params_map(_params), do: %{}
end
