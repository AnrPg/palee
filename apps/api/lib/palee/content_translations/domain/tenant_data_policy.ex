defmodule Palee.ContentTranslations.Domain.TenantDataPolicy do
  @moduledoc """
  ContentTranslations tenant data retention and purge policy (ADR-117, ADR-500).

  Translations of a business's own texts are operational data with no
  retention obligation once the business leaves.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "content_translations",
            purge_order: 6,
            disposition: :purge,
            excluded_columns: [],
            basis:
              "Translations of the business's own website texts are operational data with no retention obligation.",
            tables: [%{table: "content_translations"}]
          })

  def policy, do: @policy
end
