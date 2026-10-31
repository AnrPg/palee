defmodule Palee.Channels.Domain.TenantDataPolicy do
  @moduledoc """
  Channels tenant data retention and purge policy (ADR-117, ADR-348).

  Phone numbers, consents and sent texts are personal data with no
  retention obligation: purged with the tenant. The provider secret and the
  webhook token never leave the database.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "channels",
            purge_order: 68,
            disposition: :purge,
            excluded_columns: ["secret", "webhook_salt"],
            basis:
              "SMS, Viber and WhatsApp messages, the numbers they went to and the people's consents are communication data with no retention obligation; the box's provider secret is encrypted at rest and purged with the tenant.",
            tables: [
              %{table: "channel_message_events"},
              %{table: "channel_messages"},
              %{table: "channel_consents"},
              %{table: "channel_templates"},
              %{table: "channel_contacts"},
              %{table: "channel_connections"}
            ]
          })

  def policy, do: @policy
end
