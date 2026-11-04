defmodule Palee.ReviewAsks.Domain.TenantDataPolicy do
  @moduledoc """
  Review asks tenant data retention and purge policy (ADR-117, ADR-355).

  Asks and opt-outs are operational data with no retention obligation; in-app
  reviews (ADR-386), the reports on them and the Palee team's decisions
  (ADR-397) and the Google listing snapshot (ADR-387) too. Reports and
  decisions go before the reviews they point at.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "review_asks",
            purge_order: 6,
            disposition: :purge,
            basis:
              "Google review asks, opt-outs, the Place ID, in-app reviews with their reports and moderation decisions, and the Google listing snapshot are operational data with no retention obligation.",
            tables: [
              %{table: "box_review_reports"},
              %{table: "box_review_decisions"},
              %{table: "box_reviews"},
              %{table: "google_place_snapshots"},
              %{table: "review_asks"},
              %{table: "review_ask_opt_outs"},
              %{table: "review_ask_settings"}
            ]
          })

  def policy, do: @policy
end
