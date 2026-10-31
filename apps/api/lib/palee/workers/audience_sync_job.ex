defmodule Palee.Workers.AudienceSyncJob do
  @moduledoc "ADR-380: one Mailchimp/Brevo sync of one box (after a consent change or on request)."

  use Oban.Worker,
    queue: :integrations,
    max_attempts: 3,
    unique: [period: 60, keys: [:organization_id]]

  alias Palee.Application.Integrations.AudienceSync

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) when is_binary(organization_id) do
    _result = AudienceSync.run(%{organization_id: organization_id})
    :ok
  end
end
