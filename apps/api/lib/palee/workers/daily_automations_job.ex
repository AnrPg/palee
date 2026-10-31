defmodule Palee.Workers.DailyAutomationsJob do
  @moduledoc """
  ADR-346/345: hourly, queues each box's daily automatic messages once its
  local send hour has come (missed classes, renewal reminders, birthdays),
  and deletes lost leads that have not moved for two years. Idempotent:
  later runs the same day queue nothing new.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 1_800]

  require Logger

  alias Palee.Application.Automations.DailyAutomations
  alias Palee.{Automations, Leads, Organizations}

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> run(%{organization_id: organization.id}) end)

    :ok
  end

  @doc "Runs for one box (`context` carries its id)."
  def run(context, now \\ Automations.now()) do
    queued = DailyAutomations.run(context, now)
    Leads.purge_stale(context, now)
    queued
  rescue
    error ->
      Logger.error(
        "daily automations failed for #{context.organization_id}: #{Exception.message(error)}"
      )

      0
  end
end
