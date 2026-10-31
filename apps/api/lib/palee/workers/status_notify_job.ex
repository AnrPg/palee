defmodule Palee.Workers.StatusNotifyJob do
  @moduledoc """
  ADR-364: emails one incident update to confirmed subscribers, one batch
  per job; a full batch queues the next one after its last subscriber.
  Each email goes through the outbox (ADR-203) with an idempotency key per
  update and subscriber, so a retry never sends twice.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [period: 3_600, fields: [:worker, :args]]

  alias Palee.Application.ServiceStatusJobs

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"update_id" => update_id} = args}) do
    case ServiceStatusJobs.notify(update_id, Map.get(args, "after_id")) do
      {:ok, :done} ->
        :ok

      {:ok, {:more, last_id}} ->
        {:ok, _job} =
          %{"update_id" => update_id, "after_id" => last_id} |> new() |> Oban.insert()

        :ok

      {:error, :not_found} ->
        {:cancel, :update_not_found}
    end
  end
end
