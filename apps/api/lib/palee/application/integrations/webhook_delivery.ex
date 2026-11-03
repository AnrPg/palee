defmodule Palee.Application.Integrations.WebhookDelivery do
  @moduledoc """
  Sending what is in the webhook outbox (ADR-379): right after an event (a
  job per box), every minute for retries (only boxes with deliveries due),
  and at once for «Δοκιμή» and «Ξανά». Without background jobs (tests,
  one-off tasks) it sends inline. A webhook Palee turns off for failing is
  told to the staff who manage settings.
  """

  require Logger

  alias Palee.Application.Integrations.ConnectionNotices
  alias Palee.Integrations
  alias Palee.Workers.DeliverWebhooksJob

  @doc "Sends the box's due deliveries (or one) soon."
  def schedule(%{organization_id: organization_id} = context, delivery_id \\ nil) do
    if Application.get_env(:palee, :start_oban, true) do
      %{"organization_id" => organization_id, "delivery_id" => delivery_id}
      |> DeliverWebhooksJob.new()
      |> Oban.insert()

      :ok
    else
      {:ok, _counts} = deliver(context, delivery_id || :due)
      :ok
    end
  end

  @doc """
  Sends now: `{:ok, %{sent, delivered, failed, disabled}}`. When a webhook
  is turned off for failing, the staff who manage settings hear of it
  (bell and email).
  """
  def deliver(context, which \\ :due, now \\ DateTime.utc_now()) do
    with {:ok, %{disabled: disabled}} = result <- Integrations.deliver(context, which, now) do
      Enum.each(disabled, &ConnectionNotices.webhook_disabled(context, &1, now))
      result
    end
  end

  @doc "The minute sweep: every box with deliveries due."
  def sweep(now \\ DateTime.utc_now()) do
    now
    |> Integrations.due_organizations()
    |> Enum.each(fn organization_id ->
      try do
        deliver(%{organization_id: organization_id}, :due, now)
      rescue
        error ->
          Logger.error(
            "webhook delivery failed for #{organization_id}: #{Exception.message(error)}"
          )
      end
    end)

    :ok
  end
end
