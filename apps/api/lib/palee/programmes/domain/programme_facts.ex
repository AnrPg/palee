defmodule Palee.Programmes.Domain.ProgrammeFacts do
  @moduledoc """
  ADR-542: the facts a programme page shows next to its weeks, derived from
  its WODs, pure.

    * **κύριος εξοπλισμός** (`equipment`): the equipment keys its WODs need,
      the most used first (by the number of sessions that need it, ties in
      vocabulary order), at most #{5}. `none` is shown only when every known
      exercise needs nothing.
    * **περίπου ανά προπόνηση** (`minutes_per_session`): the mean length of a
      training day (the WODs of a day added up), rounded to 5 minutes; nil
      unless **every** WOD of the programme has a duration.

  The author adds or removes equipment on the programme (`equipment` and
  `equipment_removed`, vocabulary keys): the author's choice wins over the
  derived list key by key, so a later change of the WODs still shows up
  for the keys the author did not decide (`effective_equipment/3`).
  """

  @max_equipment 5
  @max_added 10

  def max_equipment, do: @max_equipment
  def max_added, do: @max_added

  @doc """
  The facts of `days` (`[%{"day", "workout_id"}]`), with `workouts`
  `%{workout_id => %{equipment: [key], duration_seconds: integer | nil}}`
  and `order` the vocabulary (for ties). A WOD missing from `workouts` has
  no known equipment and no duration.

  `%{"equipment" => [key], "minutes_per_session" => integer | nil}` (string
  keys: it is stored on the published version).
  """
  def derive(days, workouts, order \\ []) when is_list(days) and is_map(workouts) do
    by_day = Enum.group_by(days, & &1["day"], & &1["workout_id"])

    %{
      "equipment" => equipment(by_day, workouts, order),
      "minutes_per_session" => minutes(by_day, workouts)
    }
  end

  defp equipment(by_day, workouts, order) do
    rank = order |> Enum.with_index() |> Map.new()

    counts =
      by_day
      |> Enum.flat_map(fn {_day, ids} ->
        ids |> Enum.flat_map(&(get_in(workouts, [&1, :equipment]) || [])) |> Enum.uniq()
      end)
      |> Enum.frequencies()

    keys = Map.keys(counts)
    keys = if keys == ["none"], do: keys, else: List.delete(keys, "none")

    keys
    |> Enum.sort_by(&{-Map.fetch!(counts, &1), Map.get(rank, &1, map_size(rank)), &1})
    |> Enum.take(@max_equipment)
  end

  defp minutes(by_day, _workouts) when by_day == %{}, do: nil

  defp minutes(by_day, workouts) do
    totals =
      Enum.map(by_day, fn {_day, ids} ->
        Enum.map(ids, &get_in(workouts, [&1, :duration_seconds]))
      end)

    if Enum.all?(totals, fn seconds -> Enum.all?(seconds, &(is_integer(&1) and &1 > 0)) end) do
      mean = (totals |> Enum.map(&Enum.sum/1) |> Enum.sum()) / length(totals) / 60
      max(5, round(mean / 5) * 5)
    end
  end

  @doc """
  The equipment shown: the author's added keys first, then the derived
  ones the author did not remove (no duplicates), at most
  #{@max_equipment + @max_added}.
  """
  def effective_equipment(derived, added, removed) do
    added = Enum.uniq(added || [])
    (added ++ ((derived || []) -- ((removed || []) -- added))) |> Enum.uniq()
  end

  @doc "Checks the author's lists against the vocabulary."
  def check_lists(added, removed, vocabulary) do
    cond do
      not valid_list?(added, vocabulary, @max_added) -> {:error, :invalid_equipment}
      not valid_list?(removed, vocabulary, length(vocabulary)) -> {:error, :invalid_equipment}
      true -> :ok
    end
  end

  defp valid_list?(nil, _vocabulary, _max), do: true

  defp valid_list?(list, vocabulary, max) when is_list(list),
    do: length(list) <= max and Enum.all?(list, &(&1 in vocabulary))

  defp valid_list?(_list, _vocabulary, _max), do: false
end
