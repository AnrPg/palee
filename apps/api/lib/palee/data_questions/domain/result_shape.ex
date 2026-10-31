defmodule Palee.DataQuestions.Domain.ResultShape do
  @moduledoc """
  What one query result looks like to the model and to the asker
  (ADR-361), pure.

    * The model gets `ref` (q1, q2…), the query, the resolved arguments, a
      `summary` of numbers and at most #{20} rows, where people are only
      opaque refs (`P1`, `P2`…): no name, id or contact ever reaches the
      model. Money is given in currency units (`amount`), not cents.
    * The asker gets a table built by the server from the same rows, with
      names, so the figures they read never pass through the model.
    * People queries also yield the person ids, for the follow-up action
      the answer offers (message them, CP-C2), which a human then confirms.
  """

  alias Palee.Llm.Domain.Untrusted

  @model_rows 20
  @hidden ~w(user_id name)

  @type raw :: %{summary: map(), rows: [map()]}

  def model_rows, do: @model_rows

  @doc "The content sent back to the model for one result."
  def for_model(ref, query, params, %{summary: summary, rows: rows}) do
    shown = Enum.take(rows, @model_rows)

    %{
      "ref" => ref,
      "query" => query.name,
      "arguments" => Untrusted.data(params),
      "summary" => summary |> money() |> Untrusted.data(80),
      "rows" =>
        shown
        |> Enum.with_index(1)
        |> Enum.map(fn {row, index} -> model_row(row, index, query) end),
      "rows_total" => length(rows),
      "rows_shown" => length(shown)
    }
  end

  defp model_row(row, index, %{people: true}) do
    row
    |> Map.drop(@hidden)
    |> money()
    |> Map.put("person", "P#{index}")
    |> Untrusted.data(80)
  end

  defp model_row(row, _index, _query),
    do: row |> Map.drop(@hidden) |> money() |> Untrusted.data(80)

  @doc "The table the asker sees for one result (names included for people queries)."
  def table(ref, query, %{rows: rows}) do
    columns =
      case rows do
        [first | _] -> first |> Map.keys() |> Enum.reject(&(&1 == "user_id")) |> order()
        [] -> []
      end

    %{
      ref: ref,
      query: query.name,
      columns: columns,
      rows:
        rows
        |> Enum.with_index(1)
        |> Enum.map(fn {row, index} ->
          row = Map.drop(row, ["user_id"])
          if query.people, do: Map.put(row, "person", "P#{index}"), else: row
        end)
    }
  end

  @doc "The people of a people query, for the follow-up action."
  def people(%{people: true}, %{rows: rows}),
    do: rows |> Enum.map(&Map.get(&1, "user_id")) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  def people(_query, _raw), do: []

  @doc "Every number a cited result holds, as the grounding check accepts them."
  def numbers(%{} = content) do
    content
    |> Map.take(["arguments", "summary", "rows", "rows_total"])
    |> collect([])
  end

  defp collect(value, acc) when is_integer(value) or is_float(value), do: [value | acc]

  defp collect(value, acc) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> [date.year, date.month, date.day | acc]
      _other -> acc
    end
  end

  defp collect(%{} = map, acc), do: Enum.reduce(map, acc, fn {_k, v}, acc -> collect(v, acc) end)
  defp collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect/2)
  defp collect(_value, acc), do: acc

  defp money(%{} = map) do
    Map.new(map, fn
      {key, value} when is_integer(value) ->
        if String.ends_with?(key, "_cents"),
          do: {String.replace_suffix(key, "_cents", ""), Float.round(value / 100, 2)},
          else: {key, value}

      pair ->
        pair
    end)
  end

  defp order(columns) do
    {first, rest} = Enum.split_with(columns, &(&1 in ["name", "package", "class_type", "month"]))
    first ++ Enum.sort(rest)
  end
end
