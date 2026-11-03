defmodule Palee.Workers.ProgrammeSweepJob do
  @moduledoc "Hourly: programme purchases complete after their last day; abandoned checkouts close (ADR-371)."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 1_800]

  alias Palee.Application.Programmes.Sweep

  @impl Oban.Worker
  def perform(_job) do
    Sweep.call()
    :ok
  end
end
