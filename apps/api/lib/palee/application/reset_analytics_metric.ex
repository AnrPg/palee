defmodule Palee.Application.ResetAnalyticsMetric do
  @moduledoc """
  ADR-462 §4/§5: resets one metric. A reset never deletes data: it stores a
  baseline and the metric counts only what happened after it.

    * `:organization` - a box metric (`POST /admin/analytics/metrics/:key/
      reset`), by the owner or an admin only (`reset_analytics`, never
      grantable). Recorded in the box's audit trail
      (`analytics_metric_reset`).
    * `:member` - the member's own Πρόοδος stat (`POST /me/progress/metrics/
      :key/reset`). It changes only what that member sees, never the box's
      analytics, leaderboards or a coach's view; the member's reset history
      is its record.
  """

  alias Palee.{Analytics, Organizations}
  alias Palee.Application.TrackAnalyticsEvent

  def call(context, scope, metric_key, now \\ DateTime.utc_now())

  def call(context, :organization, metric_key, now) do
    with :ok <- authorize(context),
         {:ok, metric} <- Analytics.resettable_metric(:organization, metric_key),
         {:ok, reset} <-
           Analytics.record_metric_reset(context, :organization, %{
             metric_key: metric.key,
             reset_at: now,
             reset_by: context.user_id
           }) do
      TrackAnalyticsEvent.call("analytics_metric_reset", context, reset)
      {:ok, reset}
    end
  end

  def call(%{user_id: user_id} = context, :member, metric_key, now) when is_binary(user_id) do
    with {:ok, metric} <- Analytics.resettable_metric(:member, metric_key) do
      Analytics.record_metric_reset(context, :member, %{
        metric_key: metric.key,
        reset_at: now,
        reset_by: user_id
      })
    end
  end

  def call(_context, _scope, _metric_key, _now), do: {:error, :forbidden}

  @doc false
  def authorize(context) do
    if Organizations.can?(context, :reset_analytics), do: :ok, else: {:error, :forbidden}
  end
end
