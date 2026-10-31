defmodule Palee.Workers.DeliverChannelMessagesJob do
  @moduledoc """
  ADR-348: sends due SMS, Viber and WhatsApp messages. With an
  `organization_id` it serves that box (right after a send or a retry);
  without one (cron, every minute) it sweeps every active box, so retries
  and messages held for quiet hours never depend on a request. Claims are
  row-locked, so overlapping runs are safe.
  """

  use Oban.Worker,
    queue: :channels,
    max_attempts: 3,
    unique: [period: 30, keys: [:organization_id, :message_id]]

  require Logger

  alias Palee.Application.Channels.ChannelDelivery

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id} = args})
      when is_binary(organization_id) do
    ChannelDelivery.deliver(organization_id, args["message_id"] || :due)
  end

  def perform(_job), do: ChannelDelivery.sweep()
end
