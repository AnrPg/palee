defmodule Palee.Application.Channels.ChannelDelivery do
  @moduledoc """
  The system use case behind `DeliverChannelMessagesJob` (ADR-348 §5):
  deliver one box's due messages, or sweep every active box.
  """

  require Logger

  alias Palee.Channels
  alias Palee.Organizations

  @doc "Every active box's due messages (the cron sweep)."
  def sweep(now \\ DateTime.utc_now()) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> deliver(organization.id, :due, now) end)

    :ok
  end

  @doc "One box's due messages (or only `which`). Crashes are logged, never retried here."
  def deliver(organization_id, which, now \\ DateTime.utc_now()) do
    {:ok, _counts} = Channels.deliver(%{organization_id: organization_id}, which, now)
    :ok
  rescue
    error ->
      Logger.error("channel delivery failed for #{organization_id}: #{Exception.message(error)}")
      :ok
  end
end
