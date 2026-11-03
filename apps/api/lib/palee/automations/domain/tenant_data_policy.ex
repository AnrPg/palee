defmodule Palee.Automations.Domain.TenantDataPolicy do
  @moduledoc """
  Automations tenant data retention and purge policy (ADR-117, ADR-346).

  The box's recipe settings, the outbox of automatic messages and what box
  members chose about them are operational data with no retention
  obligation. Purged before Leads, which deliveries reference.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "automations",
            purge_order: 21,
            disposition: :purge,
            basis:
              "Automation settings, the automatic-message outbox and box members' choices about it are operational data with no retention obligation; purged before Leads, which deliveries reference.",
            tables: [
              %{table: "automation_deliveries"},
              %{table: "automation_member_preferences"},
              %{table: "box_automations"}
            ]
          })

  def policy, do: @policy
end
