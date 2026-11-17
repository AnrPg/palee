defmodule Palee.Workers.SettlePackageRemovalJob do
  @moduledoc """
  ADR-660: settles a «Αφαίρεση πακέτου» once its undo minute has passed: the
  member's upcoming bookings are cancelled and they are told. An undone
  removal is skipped. Runs again safely: the removal is settled and told
  once.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [keys: [:removal_id], period: :infinity, states: :incomplete]

  require Logger

  alias Palee.Application.{OwnershipKeys, PackageRemoval}
  alias Palee.Finance.Domain.PackageRemovalPolicy

  @margin_seconds 5

  @doc "Schedules the settle step after the undo minute (no-op without Oban)."
  def schedule(organization_id, removal_id) do
    if Oban.whereis(Oban) do
      %{organization_id: organization_id, removal_id: removal_id}
      |> new(schedule_in: PackageRemovalPolicy.undo_seconds() + @margin_seconds)
      |> Oban.insert()
      |> case do
        {:ok, _job} -> :ok
        {:error, reason} -> Logger.warning("package_removal_schedule_failed #{inspect(reason)}")
      end
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, %{"organization_id" => organization_id, "removal_id" => removal_id}} <-
           OwnershipKeys.require_tenant_args(args) do
      PackageRemoval.settle(%{organization_id: organization_id}, removal_id)
    end
  end
end
