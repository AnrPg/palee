defmodule Palee.Gamification.Domain.ScorePercentile do
  @moduledoc """
  ADR-356 (CP-D2): where each ranked result stands among the results it was
  ranked with.

    * `percentile` – the share of the other results this one beat
      (0–100, ties beat nobody they tie with);
    * `top_percent` – «στο top X%»: the share of results ranked at this
      place or better, rounded up (the single best of ten is top 10%).

  Both are nil below `min_results/0` results: with three people a
  percentile says more about who came than about the score, and it would
  let anyone work out the others' places.
  """

  @min_results 5

  def min_results, do: @min_results

  @doc """
  Adds `percentile` and `top_percent` to rows that carry a `rank` (1 is
  best; tied rows share a rank). Rows without a rank get nil.
  """
  @spec annotate([map()]) :: [map()]
  def annotate(rows) when is_list(rows) do
    ranks = rows |> Enum.map(& &1.rank) |> Enum.reject(&is_nil/1)
    total = length(ranks)

    Enum.map(rows, fn row ->
      Map.merge(row, standing(row.rank, ranks, total))
    end)
  end

  @doc "The standing of one rank among `ranks` (all ranks of the slice)."
  @spec standing(pos_integer() | nil, [pos_integer()], non_neg_integer()) :: map()
  def standing(nil, _ranks, _total), do: %{percentile: nil, top_percent: nil}

  def standing(_rank, _ranks, total) when total < @min_results,
    do: %{percentile: nil, top_percent: nil}

  def standing(rank, ranks, total) do
    worse = Enum.count(ranks, &(&1 > rank))
    at_or_better = Enum.count(ranks, &(&1 <= rank))

    %{
      percentile: div(worse * 100, total - 1) |> min(100),
      top_percent: ceil_div(at_or_better * 100, total) |> max(1)
    }
  end

  defp ceil_div(a, b), do: div(a + b - 1, b)
end
