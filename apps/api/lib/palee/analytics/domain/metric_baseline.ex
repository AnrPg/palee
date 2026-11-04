defmodule Palee.Analytics.Domain.MetricBaseline do
  @moduledoc """
  ADR-462 §4/§5: a reset never deletes data. It stores a baseline (the
  moment of the reset) and every metric counts only data after its active
  baseline: the period starts at the later of the period's own start and
  the baseline. The previous period is cut the same way; when the baseline
  is after its end there is nothing to compare with and `previous` is nil.

  Windows are UTC `[start, finish)` pairs; the gym-local dates of the
  filter are turned into them once by the caller (ADR-179).
  """

  @type window :: {DateTime.t(), DateTime.t()}

  @doc """
  The current and previous windows of a metric given its baseline
  (`nil` = never reset): `%{current: window, previous: window | nil, since: DateTime | nil}`.
  """
  def windows(%{current: current, previous: previous}, baseline) do
    %{
      current: cut(current, baseline),
      previous: cut_previous(previous, baseline),
      since: baseline
    }
  end

  defp cut(window, nil), do: window

  defp cut({start, finish}, %DateTime{} = baseline) do
    cond do
      DateTime.compare(baseline, finish) != :lt -> {finish, finish}
      DateTime.compare(baseline, start) == :gt -> {baseline, finish}
      true -> {start, finish}
    end
  end

  defp cut_previous(window, nil), do: window

  defp cut_previous({_start, finish} = window, %DateTime{} = baseline) do
    if DateTime.compare(baseline, finish) != :lt, do: nil, else: cut(window, baseline)
  end

  @doc """
  The active baseline of each metric key from reset rows (`%{metric_key,
  reset_at, undone_at}`): the latest reset that was not undone.
  """
  def active(resets) when is_list(resets) do
    resets
    |> Enum.filter(&is_nil(&1.undone_at))
    |> Enum.group_by(& &1.metric_key)
    |> Map.new(fn {key, rows} ->
      {key, rows |> Enum.map(& &1.reset_at) |> Enum.max(DateTime)}
    end)
  end

  @doc """
  A metric's response entry: `value`, `previous`, `delta` (numbers only),
  `since` (the active baseline, ISO-8601) and `suppressed`.
  """
  def entry(metric, current, previous, since) do
    suppressed? = suppressed?(current)

    %{
      key: metric.key,
      unit: metric.unit,
      kind: metric.kind,
      since: since && DateTime.to_iso8601(since),
      suppressed: suppressed?,
      value: if(suppressed?, do: nil, else: value(current)),
      previous: if(suppressed?(previous), do: nil, else: value(previous)),
      previous_suppressed: suppressed?(previous),
      delta: if(suppressed?, do: nil, else: delta(value(current), value(previous))),
      rows: if(suppressed?, do: [], else: rows(current)),
      previous_rows: if(suppressed?(previous), do: [], else: rows(previous))
    }
  end

  defp suppressed?(%{suppressed: true}), do: true
  defp suppressed?(_value), do: false

  defp value(%{value: value}), do: value
  defp value(_value), do: nil

  defp rows(%{rows: rows}) when is_list(rows), do: rows
  defp rows(_value), do: []

  defp delta(current, previous) when is_number(current) and is_number(previous),
    do: round_number(current - previous)

  defp delta(_current, _previous), do: nil

  defp round_number(value) when is_float(value), do: Float.round(value, 2)
  defp round_number(value), do: value
end
