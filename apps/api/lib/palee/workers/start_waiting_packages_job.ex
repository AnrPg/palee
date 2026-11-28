defmodule Palee.Workers.StartWaitingPackagesJob do
  @moduledoc """
  ADR-795: hourly, starts every package that waits for its member's first
  class when that class is over and nobody marked «Δεν ήρθε» (a «Ήρθε» or a
  WOD result starts it at once, `Palee.Application.Finance.PackageStarts`).
  """

  use Oban.Worker, queue: :payments, max_attempts: 3, unique: [period: 300]

  require Logger

  alias Palee.Application.Finance.PackageStarts
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> run(%{organization_id: organization.id}) end)

    :ok
  end

  @doc "Runs the sweep for one organization (`context` carries its id)."
  def run(context, now \\ DateTime.utc_now()) do
    PackageStarts.sweep(context, now)
  rescue
    error ->
      Logger.error(
        "waiting package starts failed for #{context.organization_id}: #{Exception.message(error)}"
      )

      :error
  end
end
