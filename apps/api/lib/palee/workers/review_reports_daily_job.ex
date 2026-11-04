defmodule Palee.Workers.ReviewReportsDailyJob do
  @moduledoc """
  ADR-397, daily: removed review texts go after 6 months, and the Palee team
  gets a summary email while reports wait
  (`Application.ReviewAsks.ReviewReportsDaily.run/1`).
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  require Logger

  alias Palee.Application.ReviewAsks.ReviewReportsDaily

  @impl Oban.Worker
  def perform(_job) do
    %{cleared: cleared, summary: summary} = ReviewReportsDaily.run()
    Logger.info("review_reports_daily cleared=#{cleared} summary=#{inspect(elem_or(summary))}")
    :ok
  end

  defp elem_or({status, _value}), do: status
  defp elem_or(value), do: value
end
