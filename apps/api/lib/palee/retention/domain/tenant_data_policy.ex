defmodule Palee.Retention.Domain.TenantDataPolicy do
  @moduledoc """
  Retention («Σε κίνδυνο») tenant data policy (ADR-117, ADR-347).

  Risk scores are derived daily from attendance, bookings and payments and
  can be recomputed at any time; no retention obligation. The staff action
  log (ADR-384) goes with them.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "retention",
            purge_order: 22,
            disposition: :purge,
            basis:
              "Risk scores are derived daily from attendance, bookings and payments and can be recomputed; no retention obligation.",
            tables: [%{table: "retention_risk_actions"}, %{table: "retention_risks"}]
          })

  def policy, do: @policy
end
