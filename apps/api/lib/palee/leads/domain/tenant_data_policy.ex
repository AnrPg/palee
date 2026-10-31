defmodule Palee.Leads.Domain.TenantDataPolicy do
  @moduledoc """
  Leads tenant data retention and purge policy (ADR-117, ADR-344).

  Leads, their tasks and history are the box's own sales records with no
  retention obligation; lost leads are also deleted on their own after
  `Palee.Leads.stale_after_days/0` (ADR-345). Purged after Automations,
  whose deliveries point at leads.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "leads",
            purge_order: 23,
            disposition: :purge,
            basis:
              "Leads, their tasks and history are operational sales records with no retention obligation; purged after Automations, whose deliveries reference leads.",
            tables: [
              %{table: "lead_events"},
              %{table: "lead_tasks"},
              %{table: "leads"}
            ]
          })

  def policy, do: @policy
end
