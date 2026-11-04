defmodule Palee.Application.UndoAnalyticsMetricReset do
  @moduledoc """
  ADR-462: undoes a reset. The row stays (`undone_at`, `undone_by`), so
  the history is complete, and the metric falls back to its previous
  baseline (or none). A box undo is the owner's or an admin's and goes to
  the audit trail (`analytics_metric_reset_undone`); a member undoes only
  their own resets.
  """

  alias Palee.Analytics
  alias Palee.Application.{ResetAnalyticsMetric, TrackAnalyticsEvent}

  def call(context, scope, id, now \\ DateTime.utc_now())

  def call(context, :organization, id, now) do
    with :ok <- ResetAnalyticsMetric.authorize(context),
         {:ok, reset} <- Analytics.undo_metric_reset(context, :organization, id, now) do
      TrackAnalyticsEvent.call("analytics_metric_reset_undone", context, reset)
      {:ok, reset}
    end
  end

  def call(%{user_id: user_id} = context, :member, id, now) when is_binary(user_id),
    do: Analytics.undo_metric_reset(context, :member, id, now)

  def call(_context, _scope, _id, _now), do: {:error, :forbidden}
end
