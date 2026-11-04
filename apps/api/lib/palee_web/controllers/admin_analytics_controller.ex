defmodule PaleeWeb.AdminAnalyticsController do
  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.{
    GetAdminAnalyticsSummary,
    ListAnalyticsMetricResets,
    ResetAnalyticsMetric,
    UndoAnalyticsMetricReset
  }

  alias PaleeWeb.Schemas.{AnalyticsMetrics, LocationScope}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Analytics"])
  security([%{"bearerAuth" => []}])

  operation(:summary,
    summary: "Στατιστικά: KPIs of a period with the previous one, filtered (ADR-462)",
    parameters: [LocationScope.filter_parameter() | AnalyticsMetrics.filter_parameters()],
    responses: [
      ok:
        {"Analytics summary", "application/json",
         AnalyticsMetrics.summary_response("AdminAnalyticsSummary")}
    ]
  )

  def summary(conn, params) do
    with {:ok, payload} <- GetAdminAnalyticsSummary.call(conn.assigns.tenant_context, params) do
      json(conn, payload)
    end
  end

  operation(:reset_metric,
    summary: "Reset one box metric: count only data from now on (owner and admins, ADR-462)",
    parameters: [AnalyticsMetrics.metric_key_parameter()],
    responses: [
      created: {"Reset", "application/json", AnalyticsMetrics.reset_response()}
    ]
  )

  def reset_metric(conn, %{"metric_key" => key}) do
    with {:ok, reset} <-
           ResetAnalyticsMetric.call(conn.assigns.tenant_context, :organization, key) do
      conn |> put_status(:created) |> json(%{reset: reset})
    end
  end

  operation(:undo_reset,
    summary: "Undo a box metric reset (owner and admins, ADR-462)",
    parameters: [AnalyticsMetrics.reset_id_parameter()],
    responses: [ok: {"Reset", "application/json", AnalyticsMetrics.reset_response()}]
  )

  def undo_reset(conn, %{"id" => id}) do
    with {:ok, reset} <-
           UndoAnalyticsMetricReset.call(conn.assigns.tenant_context, :organization, id) do
      json(conn, %{reset: reset})
    end
  end

  operation(:resets,
    summary: "The box's metric reset history, with each metric before its reset (ADR-462)",
    parameters: AnalyticsMetrics.history_parameters(),
    responses: [
      ok:
        {"Reset history", "application/json",
         AnalyticsMetrics.history_response("AdminAnalyticsResetHistory")}
    ]
  )

  def resets(conn, params) do
    with {:ok, page} <-
           ListAnalyticsMetricResets.call(conn.assigns.tenant_context, :organization, params) do
      json(conn, page)
    end
  end
end
