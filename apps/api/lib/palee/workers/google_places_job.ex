defmodule Palee.Workers.GooglePlacesJob do
  @moduledoc """
  ADR-387: refreshes the Google listings that are due (each box with a Place
  ID about once a day; a failed read backs off). Runs hourly from cron.
  """

  use Oban.Worker, queue: :box_site, max_attempts: 1, unique: [period: 600]

  require Logger

  alias Palee.Application.ReviewAsks.ReviewAskAdmin
  alias Palee.ReviewAsks

  @impl Oban.Worker
  def perform(_job) do
    ReviewAsks.clock().now()
    |> ReviewAsks.place_due_organizations()
    |> Enum.each(&refresh/1)

    :ok
  end

  defp refresh(organization_id) do
    context = %{organization_id: organization_id}

    case ReviewAsks.settings(context).google_place_id do
      nil -> :ok
      place_id -> ReviewAskAdmin.refresh(context, place_id)
    end
  rescue
    error ->
      Logger.error("google places job failed for #{organization_id}: #{Exception.message(error)}")
      :ok
  end
end
