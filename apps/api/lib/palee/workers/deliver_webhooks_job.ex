defmodule Palee.Workers.DeliverWebhooksJob do
  @moduledoc """
  ADR-379: sends webhook deliveries. With an `organization_id` it serves that
  box (right after an event, a test or a replay); without one (cron, every
  minute) it visits only the boxes with deliveries due. Deliveries are
  leased, so overlapping runs never send twice.
  """

  use Oban.Worker,
    queue: :integrations,
    max_attempts: 3,
    unique: [period: 10, keys: [:organization_id, :delivery_id]]

  require Logger

  alias Palee.Application.Integrations.WebhookDelivery

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id} = args})
      when is_binary(organization_id) do
    {:ok, _counts} =
      WebhookDelivery.deliver(%{organization_id: organization_id}, args["delivery_id"] || :due)

    :ok
  rescue
    error ->
      Logger.error("webhook delivery failed for #{organization_id}: #{Exception.message(error)}")
      :ok
  end

  def perform(_job), do: WebhookDelivery.sweep()
end
