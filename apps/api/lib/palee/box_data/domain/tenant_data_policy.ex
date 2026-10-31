defmodule Palee.BoxData.Domain.TenantDataPolicy do
  @moduledoc "The box's own data exports (ADR-365): their records go with the box (ADR-117)."

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "box_data",
            purge_order: 3,
            disposition: :purge,
            basis:
              "Records of the box's own data exports (who asked, when, the file's checksum); the files live under the tenant prefix and go with the tenant objects.",
            tables: [%{table: "box_data_exports"}],
            excluded_columns: []
          })

  def policy, do: @policy
end
