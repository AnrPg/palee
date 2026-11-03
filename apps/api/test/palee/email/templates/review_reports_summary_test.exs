defmodule Palee.Email.Templates.ReviewReportsSummaryTest do
  # ADR-397: the Palee team's daily summary of open review reports.
  use ExUnit.Case, async: true

  alias Palee.Email.Templates
  alias Palee.Email.Templates.ReviewReportsSummary

  @locales ~w(ar bg de el en es fr he it nl pt_PT ru)
  @assigns %{
    reviews: 2,
    reports: 3,
    oldest: ~U[2026-11-01 08:00:00Z],
    url: "https://palee.test/platform/review-reports"
  }

  test "is a registered account email, one a day" do
    assert {:ok, ReviewReportsSummary} = Templates.fetch(:review_reports_summary)
    assert ReviewReportsSummary.category() == :account
    assert ReviewReportsSummary.throttle().max_per_day == 1
  end

  test "every locale has every string" do
    msgids =
      Regex.scan(~r/^msgid "(.+)"$/m, File.read!("priv/gettext/review_reports.pot"),
        capture: :all_but_first
      )
      |> List.flatten()

    assert length(msgids) == 4

    for dir <- @locales do
      po = File.read!(Path.join(["priv/gettext", dir, "LC_MESSAGES", "review_reports.po"]))

      for msgid <- msgids do
        assert po =~ ~s(msgid "#{msgid}"\nmsgstr "), "#{dir} lacks #{msgid}"
        refute po =~ ~s(msgid "#{msgid}"\nmsgstr ""\n), "#{dir} leaves #{msgid} untranslated"
      end
    end
  end

  test "Greek: counts, the oldest date and the link" do
    assert ReviewReportsSummary.subject(@assigns, "el") == "Αναφορές κριτικών σε αναμονή: 2"
    text = ReviewReportsSummary.text(@assigns, "el")
    assert text =~ "3 αναφορές"
    assert text =~ "2026-11-01"
    assert text =~ "https://palee.test/platform/review-reports"
    assert ReviewReportsSummary.html(@assigns, "en") =~ "Open the queue"
  end
end
