defmodule Palee.ActivityLog.Domain.TenantDataPolicy do
  @moduledoc """
  ADR-760 tenant data policy (ADR-117): the «Αρχείο ενεργειών» is the box's
  own record of who did what, kept as long as the box exists (ANR 9A) and
  purged with the tenant: the records the law asks a closed business to
  keep are Finance's, Fiscal's and Coach pay's own rows. A deleted account's rows lose their reason and
  details (`ActivityLog.forget_person/1`).
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "activity_log",
            purge_order: 5,
            disposition: :purge,
            excluded_columns: [],
            basis:
              "The activity log records who on the staff changed what, when and why, including money and access decisions; the box keeps it for accountability for as long as it exists; the accounting records themselves are retained by their own contexts.",
            tables: [
              %{table: "activity_log_backfills"},
              %{table: "activity_log_entries"}
            ]
          })

  def policy, do: @policy
end
