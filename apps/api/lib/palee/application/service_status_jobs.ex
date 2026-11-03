defmodule Palee.Application.ServiceStatusJobs do
  @moduledoc """
  ADR-364: the status page's background work.

  * `probe/0` – one round of dependency checks, stored (every minute).
  * `sweep/0` – probe counts past the 90-day history and sign-ups never
    confirmed (daily).
  * `notify/2` – one batch of status emails for an incident update, to
    confirmed subscribers in id order; returns the last id when more remain.
    Each email has an idempotency key per update and subscriber, so a retry
    never sends twice.
  """

  require Logger

  alias Palee.{Email, Status}
  alias Palee.Application.ServiceStatusLinks

  @batch 100

  def batch_size, do: @batch

  def probe do
    results = probe_adapter().check()
    now = clock().now()

    Enum.each(results, fn %{component: component, status: status} ->
      :telemetry.execute([:palee, :status, :probe], %{count: 1}, %{
        component: component,
        status: status
      })
    end)

    Status.record_probe(results, now)
  end

  def sweep, do: {:ok, Status.sweep(clock().now())}

  @doc "`{:ok, :done}` or `{:ok, {:more, last_id}}`."
  def notify(update_id, after_id) do
    with {:ok, incident, update} <- Status.get_update_with_incident(update_id) do
      subscribers = Status.list_confirmed_subscribers(after_id, @batch)
      now = clock().now()

      Enum.each(subscribers, &send_update(&1, incident, update, now))

      if length(subscribers) == @batch,
        do: {:ok, {:more, List.last(subscribers).id}},
        else: {:ok, :done}
    end
  end

  defp send_update(subscriber, incident, update, now) do
    # ADR-366: the subscriber reads the original in its own language, else English.
    text = Status.for_reader(incident, update, subscriber.locale)

    result =
      Email.enqueue(
        :status_update,
        subscriber.email,
        %{
          kind: incident.kind,
          title: text.title,
          status: update.status,
          body: text.body,
          components: incident.components,
          scheduled_for: incident.scheduled_for,
          scheduled_until: incident.scheduled_until,
          url: ServiceStatusLinks.page_url(),
          unsubscribe_url: ServiceStatusLinks.unsubscribe_url(subscriber.id)
        },
        locale: subscriber.locale,
        idempotency_key: "status_update:#{update.id}:#{subscriber.id}",
        now: now
      )

    case result do
      {:ok, _message} ->
        :ok

      {:error, reason} ->
        Logger.info("status update #{update.id} not queued for a subscriber: #{inspect(reason)}")
    end
  end

  defp probe_adapter, do: Application.fetch_env!(:palee, :status_probe)
  defp clock, do: Application.fetch_env!(:palee, :status_clock)
end
