defmodule Palee.Application.ReviewAsks.ReviewReportsDaily do
  @moduledoc """
  ADR-397, once a day:

    * the copy of a removed review's text (and the notes on it) goes 6 months
      after the decision; the decision itself stays;
    * when reports are open, the Palee team gets one summary email (how many
      reviews and reports wait, since when) with a link to the console. No
      email when nothing waits.
  """

  alias Palee.{Email, ReviewAsks}
  alias Palee.Application.PublicURL

  @doc "Runs both; `now` for tests."
  def run(now \\ DateTime.utc_now()) do
    cleared = ReviewAsks.purge_removed_texts(ReviewAsks.removed_text_before(now))
    %{cleared: cleared, summary: summary(now)}
  end

  defp summary(now) do
    case ReviewAsks.open_report_totals() do
      %{reports: 0} ->
        :none

      totals ->
        config = ReviewAsks.moderation_config()

        case Keyword.get(config, :team_email) do
          email when is_binary(email) and email != "" ->
            Email.enqueue(
              :review_reports_summary,
              email,
              Map.put(totals, :url, PublicURL.base_url() <> "/platform/review-reports"),
              locale: Keyword.get(config, :team_locale, "el"),
              idempotency_key: "review_reports_summary:#{Date.to_iso8601(DateTime.to_date(now))}",
              now: now
            )

          _none ->
            :no_address
        end
    end
  end
end
