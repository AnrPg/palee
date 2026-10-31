defmodule Palee.Wellness.Domain.Meal do
  @moduledoc """
  Γεύμα (ADR-159 §1, vision §7.7, §8.6): a meal, optionally in a slot, «εντός»
  or «εκτός πλάνου», with an optional photo and line of text. Optional hand
  portions (palm of protein, cupped hand of carbs, fist of vegetables, thumb of fat) let a coach's plan be followed
  without weighing food. No calories, ever.

  ADR-376: `foods` names what was eaten, from a barcode scan or the
  person's own foods: up to 10 items of `name` (and optional `barcode`,
  `custom_food_id`, `portion`). A snapshot of the name, so the meal reads
  the same after the cache or the food changes.
  """

  @behaviour Palee.Wellness.Domain.EntryValue

  alias Palee.Wellness.Domain.EntryValue

  @slots Palee.Nutrition.Domain.PortionPolicy.slots()
  @main_slots ~w(breakfast lunch dinner)
  @plan_fits ~w(in_plan off_plan)
  @portions ~w(protein carbs veg fat)
  @max_portions 10

  def slots, do: @slots
  def main_slots, do: @main_slots
  def plan_fits, do: @plan_fits
  def portion_keys, do: @portions

  @impl true
  def cast(params) do
    EntryValue.collect([
      {"slot", EntryValue.one_of(params, "slot", @slots)},
      {"plan_fit", EntryValue.one_of(params, "plan_fit", @plan_fits)},
      {"note", EntryValue.text(params, "note", 280)},
      {"media_id", cast_media_id(params)},
      {"portions", portions(params)},
      {"foods", foods(params)},
      {"hunger_before", EntryValue.integer(params, "hunger_before", 1, 5)},
      {"fullness_after", EntryValue.integer(params, "fullness_after", 1, 5)}
    ])
  end

  @impl true
  def counts_at(_value, occurred_at), do: occurred_at

  def media_id(%{"media_id" => id}) when is_binary(id), do: id
  def media_id(_value), do: nil

  defp cast_media_id(params) do
    case EntryValue.get(params, "media_id") do
      nil ->
        {:ok, nil}

      value ->
        case Ecto.UUID.cast(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, %{"media_id" => "is not a media id"}}
        end
    end
  end

  @max_foods 10

  defp foods(params) do
    case EntryValue.get(params, "foods") do
      nil ->
        {:ok, nil}

      [] ->
        {:ok, nil}

      list when is_list(list) and length(list) <= @max_foods ->
        list
        |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
          case food(item) do
            {:ok, food} -> {:cont, {:ok, [food | acc]}}
            :error -> {:halt, {:error, %{"foods" => "name each food (at most #{@max_foods})"}}}
          end
        end)
        |> case do
          {:ok, foods} -> {:ok, Enum.reverse(foods)}
          error -> error
        end

      _other ->
        {:error, %{"foods" => "name each food (at most #{@max_foods})"}}
    end
  end

  defp food(item) when is_map(item) do
    name = EntryValue.get(item, "name")
    barcode = EntryValue.get(item, "barcode")
    custom_id = EntryValue.get(item, "custom_food_id")
    portion = EntryValue.get(item, "portion")

    with true <- is_binary(name) and String.trim(name) != "" and String.length(name) <= 120,
         true <- is_nil(barcode) or (is_binary(barcode) and Regex.match?(~r/^[0-9]{8,14}$/, barcode)),
         true <- is_nil(custom_id) or match?({:ok, _id}, Ecto.UUID.cast(custom_id)),
         true <- is_nil(portion) or portion in @portions do
      {:ok,
       %{"name" => String.trim(name), "barcode" => barcode, "custom_food_id" => custom_id, "portion" => portion}
       |> Enum.reject(fn {_key, value} -> is_nil(value) end)
       |> Map.new()}
    else
      _invalid -> :error
    end
  end

  defp food(_item), do: :error

  # Half portions are allowed («μισή γροθιά»); stored as numbers.
  defp portions(params) do
    case EntryValue.get(params, "portions") do
      nil ->
        {:ok, nil}

      portions when is_map(portions) ->
        portions
        |> Enum.map(fn {key, amount} -> {to_string(key), amount} end)
        |> Enum.reduce_while({:ok, %{}}, fn {key, amount}, {:ok, acc} ->
          if key in @portions and portion?(amount),
            do: {:cont, {:ok, Map.put(acc, key, amount)}},
            else:
              {:halt,
               {:error,
                %{"portions" => "use protein, carbs, veg, fat in halves up to #{@max_portions}"}}}
        end)
        |> case do
          {:ok, map} when map == %{} -> {:ok, nil}
          other -> other
        end

      _other ->
        {:error, %{"portions" => "must be an object"}}
    end
  end

  defp portion?(amount) when is_integer(amount), do: amount >= 0 and amount <= @max_portions

  defp portion?(amount) when is_float(amount),
    do: amount >= 0 and amount <= @max_portions and amount * 2 == Float.round(amount * 2)

  defp portion?(_amount), do: false
end
