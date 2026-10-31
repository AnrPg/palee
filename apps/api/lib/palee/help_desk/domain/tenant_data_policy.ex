defmodule Palee.HelpDesk.Domain.TenantDataPolicy do
  @moduledoc "Help desk tenant data retention and purge policy (ADR-117, ADR-363)."

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "help_desk",
            purge_order: 3,
            disposition: :purge,
            basis:
              "Support conversations of the box's staff with Palee and the tickets handed to the Palee team; operational, deleted with the box once exported.",
            tables: [
              %{table: "help_desk_tickets"},
              %{table: "help_desk_messages"},
              %{table: "help_desk_conversations"}
            ]
          })

  def policy, do: @policy
end
