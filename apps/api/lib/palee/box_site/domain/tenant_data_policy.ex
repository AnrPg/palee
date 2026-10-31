defmodule Palee.BoxSite.Domain.TenantDataPolicy do
  @moduledoc """
  BoxSite tenant data retention and purge policy (ADR-117, ADR-352..354).

  Site settings, custom domains, the form outbox and the consent log are
  operational data with no retention obligation once the business leaves.
  Submissions hold personal data only until handed to the leads context.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "box_site",
            purge_order: 6,
            disposition: :purge,
            basis:
              "Website settings, custom domains, the form outbox and the pseudonymous consent log are operational data with no retention obligation; personal fields of submissions are cleared once delivered to leads.",
            tables: [
              %{table: "box_site_consents"},
              %{table: "box_site_submissions"},
              %{table: "box_site_domains"},
              %{table: "box_site_settings"}
            ]
          })

  def policy, do: @policy
end
