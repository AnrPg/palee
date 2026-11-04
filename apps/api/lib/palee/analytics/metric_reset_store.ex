defmodule Palee.Analytics.MetricResetStore do
  @moduledoc """
  Facade of the ADR-462 metric baselines. A box's baselines are read and
  written in its scope, a member's own in theirs (`RepoContext.run/2` with
  only the person: account-level, across providers).
  """

  alias Palee.Infrastructure.Tenancy.RepoContext

  @default_adapter Palee.Infrastructure.Analytics.EctoMetricResetStore

  def insert_reset(context, scope, attrs),
    do: run(context, scope, fn -> adapter().insert_reset(scope, attrs) end)

  def undo_reset(context, scope, id, now),
    do: run(context, scope, fn -> adapter().undo_reset(scope, id, actor(context), now) end)

  def list_resets(context, scope, opts),
    do: run(context, scope, fn -> adapter().list_resets(scope, opts) end)

  def active_resets(context, scope),
    do: run(context, scope, fn -> adapter().active_resets(scope) end)

  defp run(context, :organization, fun), do: RepoContext.run(context, fun)

  defp run(%{user_id: user_id}, :member, fun) when is_binary(user_id),
    do: RepoContext.run(%{user_id: user_id}, fun)

  defp run(_context, _scope, _fun), do: {:error, :missing_ownership_scope}

  defp actor(%{user_id: user_id}), do: user_id
  defp actor(_context), do: nil

  defp adapter, do: Application.get_env(:palee, :metric_reset_store, @default_adapter)
end
