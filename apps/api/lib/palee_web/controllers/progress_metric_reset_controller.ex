defmodule PaleeWeb.ProgressMetricResetController do
  @moduledoc """
  ADR-462 §5: a member resets one of their own Πρόοδος stats. It changes
  only what the member sees (`/me/progress`, `/me/progress/depth`), never
  the box's analytics, leaderboards or a coach's view.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.{
    ListAnalyticsMetricResets,
    ResetAnalyticsMetric,
    UndoAnalyticsMetricReset
  }

  alias PaleeWeb.Schemas.AnalyticsMetrics

  action_fallback PaleeWeb.FallbackController

  tags(["Training Log"])
  security([%{"bearerAuth" => []}])

  operation(:reset,
    summary: "Reset one of my Πρόοδος stats: count only from now on (ADR-462)",
    parameters: [AnalyticsMetrics.metric_key_parameter()],
    responses: [created: {"Reset", "application/json", AnalyticsMetrics.reset_response()}]
  )

  def reset(conn, %{"metric_key" => key}) do
    with {:ok, reset} <- ResetAnalyticsMetric.call(conn.assigns.user_context, :member, key) do
      conn |> put_status(:created) |> json(%{reset: reset})
    end
  end

  operation(:undo,
    summary: "Undo one of my Πρόοδος resets (ADR-462)",
    parameters: [AnalyticsMetrics.reset_id_parameter()],
    responses: [ok: {"Reset", "application/json", AnalyticsMetrics.reset_response()}]
  )

  def undo(conn, %{"id" => id}) do
    with {:ok, reset} <- UndoAnalyticsMetricReset.call(conn.assigns.user_context, :member, id) do
      json(conn, %{reset: reset})
    end
  end

  operation(:index,
    summary: "My Πρόοδος reset history (ADR-462)",
    parameters: AnalyticsMetrics.history_parameters(),
    responses: [
      ok:
        {"Reset history", "application/json",
         AnalyticsMetrics.history_response("MyProgressResetHistory")}
    ]
  )

  def index(conn, params) do
    with {:ok, page} <- ListAnalyticsMetricResets.call(conn.assigns.user_context, :member, params) do
      json(conn, page)
    end
  end
end
