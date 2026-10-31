defmodule Palee.Access.Domain.TenantDataPolicy do
  @moduledoc """
  Door access tenant data retention and purge policy (ADR-117, ADR-381).

  Door controllers and the access log are operational data. The log is
  kept for #{180} days by the access sweep (data minimisation) and purged
  with the box; controller credentials and event tokens never leave the
  database.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "access",
            purge_order: 8,
            disposition: :purge,
            basis:
              "Door controllers and the entry log are operational data; the log is kept 180 days for security and purged with the box. Purged before Facility because controllers reference locations.",
            tables: [
              %{table: "access_events"},
              %{table: "door_controllers"}
            ],
            excluded_columns: ["credentials", "event_token_hash"]
          })

  def policy, do: @policy
end
