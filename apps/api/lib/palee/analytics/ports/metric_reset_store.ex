defmodule Palee.Analytics.Ports.MetricResetStore do
  @moduledoc "ADR-462: per-metric baselines (resets) of a box or a member."

  @type scope :: :organization | :member

  @callback insert_reset(scope(), map()) :: {:ok, map()} | {:error, term()}
  @callback undo_reset(scope(), String.t(), String.t() | nil, DateTime.t()) ::
              {:ok, map()} | {:error, :not_found | :already_undone}
  @callback list_resets(scope(), keyword()) :: %{entries: [map()], total: non_neg_integer()}
  @callback active_resets(scope()) :: [map()]
end
