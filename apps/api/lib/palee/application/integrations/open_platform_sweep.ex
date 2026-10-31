defmodule Palee.Application.Integrations.OpenPlatformSweep do
  @moduledoc """
  The hourly housekeeping of the open platform and door access (ADR-378..381):
  expired idempotency records, door log lines past their #{180} days, and
  email-list syncs that are due. Each box is its own unit: one failing box
  never stops the others.
  """

  require Logger

  alias Palee.{Access, Integrations, Organizations}
  alias Palee.Application.Integrations.AudienceSync

  def run(now \\ DateTime.utc_now()) do
    ids =
      Organizations.list_active_organizations_for_system()
      |> Enum.map(fn %{organization: organization} -> organization.id end)

    Enum.each(ids, fn organization_id ->
      context = %{organization_id: organization_id}

      try do
        Integrations.purge_idempotency(context, now)
        Access.purge_old_events(context, now)
      rescue
        error ->
          Logger.error("open platform sweep failed for #{organization_id}: #{Exception.message(error)}")
      end
    end)

    AudienceSync.sweep(ids, now)
    :ok
  end
end
