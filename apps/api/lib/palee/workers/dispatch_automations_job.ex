defmodule Palee.Workers.DispatchAutomationsJob do
  @moduledoc """
  ADR-346: every five minutes, sends each box's due automatic messages
  from the outbox. Claims are row-locked (`SKIP LOCKED`), so overlapping
  runs never send one message twice.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 240]

  require Logger

  alias Palee.Application.Automations.DispatchAutomations
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> run(%{organization_id: organization.id}) end)

    :ok
  end

  @doc "Runs for one box (`context` carries its id)."
  def run(context, now \\ Palee.Automations.now()) do
    DispatchAutomations.run(context, now)
  rescue
    error ->
      Logger.error(
        "automation dispatch failed for #{context.organization_id}: #{Exception.message(error)}"
      )

      %{}
  end
end
