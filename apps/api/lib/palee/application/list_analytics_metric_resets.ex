defmodule Palee.Application.ListAnalyticsMetricResets do
  @moduledoc """
  ADR-462: the reset history, newest first, paged (`page`, `per_page` up
  to 50, optional `metric_key`).

  For a box (`:organization`) each entry also carries `before`: the
  metric over the `days` (default 30) that ended at the reset, without any
  baseline, so staff can still see the old period. A member's history
  (`:member`) lists only their own resets.
  """

  alias Palee.Analytics

  @max_per_page 50

  def call(context, scope, params) when scope in [:organization, :member] do
    params = Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)

    with {:ok, page} <- positive(params["page"], 1, :page),
         {:ok, per_page} <- positive(params["per_page"], 20, :per_page),
         {:ok, days} <- positive(params["days"], 30, :days),
         {:ok, metric_key} <- metric_key(scope, params["metric_key"]) do
      per_page = min(per_page, @max_per_page)

      case Analytics.list_metric_resets(context, scope,
             limit: per_page,
             offset: (page - 1) * per_page,
             metric_key: metric_key
           ) do
        %{entries: entries, total: total} ->
          {:ok,
           %{
             entries: Enum.map(entries, &entry(context, scope, &1, min(days, 365))),
             page: page,
             per_page: per_page,
             total: total
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp entry(context, :organization, reset, days) do
    {:ok, filter} = Analytics.parse_analytics_filter(%{"days" => days}, Date.utc_today())
    from = DateTime.add(reset.reset_at, -days * 86_400, :second)

    before =
      case Analytics.kpi_over(context, filter, reset.metric_key, {from, reset.reset_at}) do
        {:ok, value} ->
          Map.merge(
            %{from: DateTime.to_iso8601(from), to: DateTime.to_iso8601(reset.reset_at)},
            value
          )

        _unknown ->
          nil
      end

    reset |> base() |> Map.put(:before, before)
  end

  defp entry(_context, :member, reset, _days), do: base(reset)

  defp base(reset) do
    %{
      id: reset.id,
      scope: reset.scope,
      metric_key: reset.metric_key,
      reset_at: reset.reset_at,
      reset_by: reset.reset_by,
      undone_at: reset.undone_at,
      undone_by: reset.undone_by,
      active: is_nil(reset.undone_at)
    }
  end

  defp metric_key(_scope, nil), do: {:ok, nil}
  defp metric_key(_scope, ""), do: {:ok, nil}

  defp metric_key(scope, key) do
    with {:ok, metric} <- Analytics.fetch_metric(scope, key), do: {:ok, metric.key}
  end

  defp positive(nil, default, _field), do: {:ok, default}
  defp positive(value, _default, _field) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive(value, default, field) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> positive(number, default, field)
      _invalid -> {:error, [{field, "must be a positive whole number"}]}
    end
  end

  defp positive(_value, _default, field),
    do: {:error, [{field, "must be a positive whole number"}]}
end
