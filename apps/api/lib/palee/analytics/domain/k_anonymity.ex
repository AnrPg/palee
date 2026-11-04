defmodule Palee.Analytics.Domain.KAnonymity do
  @moduledoc """
  ADR-462 §3: opt-in demographics (age band, gender) are only ever shown
  for groups of at least #{5} people. A smaller bucket, or any figure built
  from an age or gender selection that covers fewer people, is returned as
  `%{suppressed: true}`: never its number, not even zero.
  """

  @threshold 5

  def threshold, do: @threshold

  @doc "True when a group of `people` may be shown."
  def shown?(people) when is_integer(people), do: people >= @threshold
  def shown?(_people), do: false

  @doc "A bucket `%{key, people}` or `%{key, suppressed: true}`."
  def bucket(key, people) do
    if shown?(people),
      do: %{key: key, people: people, suppressed: false},
      else: %{key: key, suppressed: true}
  end

  @doc """
  Rows of a breakdown under an age or gender selection: a row covering
  fewer than the threshold of people (its `people`) becomes
  `%{key, suppressed: true}`. Rows without a people count are kept.
  """
  def suppress_rows(rows) when is_list(rows) do
    Enum.map(rows, fn
      %{people: people} = row when is_integer(people) ->
        if shown?(people), do: row, else: %{key: row[:key], suppressed: true}

      row ->
        row
    end)
  end

  @doc "Buckets for every key in `keys`, counted from `counts` (`%{key => people}`)."
  def buckets(keys, counts) when is_list(keys) and is_map(counts),
    do: Enum.map(keys, &bucket(&1, Map.get(counts, &1, 0)))
end
