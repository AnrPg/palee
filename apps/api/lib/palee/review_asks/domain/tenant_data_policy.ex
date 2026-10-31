defmodule Palee.ReviewAsks.Domain.TenantDataPolicy do
  @moduledoc """
  Review asks tenant data retention and purge policy (ADR-117, ADR-355).

  Asks and opt-outs are operational data with no retention obligation.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "review_asks",
            purge_order: 6,
            disposition: :purge,
            basis:
              "Google review asks, opt-outs and the Place ID are operational data with no retention obligation.",
            tables: [
              %{table: "review_asks"},
              %{table: "review_ask_opt_outs"},
              %{table: "review_ask_settings"}
            ]
          })

  def policy, do: @policy
end
