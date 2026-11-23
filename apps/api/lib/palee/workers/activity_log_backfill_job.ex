defmodule Palee.Workers.ActivityLogBackfillJob do
  @moduledoc """
  ADR-760 (11A): hourly, copies the older records of every box whose
  «Αρχείο ενεργειών» is not yet at the backfill's version
  (`Palee.ActivityLog.Backfill`). A box that is done costs one read; a
  failed box is retried by the next run (the copy is idempotent).
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 300]

  require Logger

  alias Palee.ActivityLog.Backfill
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> run(organization.id) end)

    :ok
  end

  @doc "Runs for one organization."
  def run(organization_id) do
    Backfill.run(organization_id)
  rescue
    error ->
      Logger.error(
        "activity log backfill failed for #{organization_id}: #{Exception.message(error)}"
      )

      {:error, error}
  end
end
