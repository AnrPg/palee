defmodule Palee.CoachPay.Domain.TenantDataPolicy do
  @moduledoc """
  Coach pay tenant data retention and purge policy (ADR-117, ADR-341).

  Statements are pay records the box hands to its accountant for payroll:
  kept like the box's other accounting records, purged with the tenant.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "coach_pay",
            purge_order: 82,
            disposition: :retain,
            retain_years: 10,
            excluded_columns: [],
            basis:
              "Coach pay statements are the basis of payroll and commissions, which tax and labour law ask the business to keep; the rules and periods explain them.",
            tables: [
              %{table: "coach_pay_lines"},
              %{table: "coach_pay_statements"},
              %{table: "coach_pay_periods"},
              %{table: "coach_pay_rules"}
            ]
          })

  def policy, do: @policy
end
