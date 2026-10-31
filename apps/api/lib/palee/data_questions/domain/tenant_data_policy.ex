defmodule Palee.DataQuestions.Domain.TenantDataPolicy do
  @moduledoc """
  Data questions tenant data retention and purge policy (ADR-117, ADR-361).
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "data_questions",
            purge_order: 3,
            disposition: :purge,
            basis:
              "The audit log of staff questions over the box's own data: questions, the queries run and the answers, never the rows read. Kept for the box's accountability and deleted with the box once exported.",
            tables: [%{table: "data_questions"}]
          })

  def policy, do: @policy
end
