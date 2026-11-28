defmodule Palee.Workers.ActivityLogDigestJob do
  @moduledoc """
  ADR-760 (ANR 12B), hourly: each box's owners get the summary of the
  sensitive actions of the box's yesterday once its morning has come
  (`Application.ActivityLogDigest`). Each box is read in its own repo
  scope; one box failing never stops the others. Idempotent: the runs after
  the first one of a box's day send nothing new.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 1_800]

  require Logger

  alias Palee.Application.ActivityLogDigest
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      run(%{organization_id: organization.id}, now)
    end)

    :ok
  end

  @doc "Runs for one box (`context` carries its id)."
  def run(context, now \\ DateTime.utc_now()) do
    ActivityLogDigest.run(context, now)
  rescue
    error ->
      Logger.error(
        "activity_log_digest failed for #{context.organization_id}: #{Exception.message(error)}"
      )

      :error
  end
end
