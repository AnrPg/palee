defmodule Palee.Integrations.Domain.TenantDataPolicy do
  @moduledoc """
  Open platform tenant data retention and purge policy (ADR-117, ADR-378..380).

  API keys, webhook endpoints and their delivery log, idempotency records,
  the audience connection and marketing consents are operational data with
  no retention obligation. Key hashes, webhook secrets and provider
  credentials never leave the database.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "integrations",
            purge_order: 7,
            disposition: :purge,
            basis:
              "API keys, webhooks with their delivery log, idempotency records, the email-list connection and members' marketing consents are operational data with no retention obligation; purged first because nothing else references them.",
            tables: [
              %{table: "webhook_delivery_attempts"},
              %{table: "webhook_deliveries"},
              %{table: "webhook_endpoints"},
              %{table: "idempotency_records"},
              %{table: "audience_members"},
              %{table: "audience_connections"},
              %{table: "integration_marketing_consents"},
              %{table: "api_keys"}
            ],
            excluded_columns: [
              "secret_hash",
              "previous_secret_hash",
              "secret",
              "previous_secret",
              "credentials",
              "unsubscribe_token_hash",
              "response_body"
            ]
          })

  def policy, do: @policy
end
