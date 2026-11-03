defmodule Palee.Programmes.Domain.TenantDataPolicy do
  @moduledoc """
  Programmes tenant data retention and purge policy (ADR-117, ADR-370/371).

  A purchase is the source row of a programme sale in Finance (the invoice
  line and payment point at it with `source_type = programme_purchase`), so
  purchases follow Finance's statutory retention; the programmes, their
  frozen versions, deliveries and reviews are kept with them.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "programmes",
            purge_order: 84,
            disposition: :retain,
            retain_years: 10,
            basis:
              "Programme purchases are the source documents of programme sales in Finance (invoice lines and payments point at them), so they follow Finance's statutory retention; the programmes, their published versions, the WODs delivered and the reviews are kept with them.",
            tables: [
              %{table: "programme_reviews"},
              %{table: "programme_deliveries"},
              %{table: "programme_purchases"},
              %{table: "programme_versions"},
              %{table: "programmes"}
            ]
          })

  def policy, do: @policy
end
