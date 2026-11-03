defmodule Palee.Workers.OpenPlatformSweepJob do
  @moduledoc """
  ADR-378..381, hourly for every active box: forgets expired idempotency
  records, trims the door log to #{180} days and syncs email lists that are
  due (asked for, or a day since the last sync).
  """

  use Oban.Worker, queue: :integrations, max_attempts: 1, unique: [period: 300]

  alias Palee.Application.Integrations.OpenPlatformSweep

  @impl Oban.Worker
  def perform(_job), do: OpenPlatformSweep.run()
end
