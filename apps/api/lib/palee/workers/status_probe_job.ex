defmodule Palee.Workers.StatusProbeJob do
  @moduledoc """
  ADR-364: probes every status page component (cron, every minute), or with
  `%{"sweep" => true}` deletes probe counts past the history window and
  sign-ups never confirmed (cron, daily).
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 50, fields: [:worker, :args]]

  alias Palee.Application.ServiceStatusJobs

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sweep" => true}}) do
    {:ok, _counts} = ServiceStatusJobs.sweep()
    :ok
  end

  def perform(%Oban.Job{}), do: ServiceStatusJobs.probe()

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
