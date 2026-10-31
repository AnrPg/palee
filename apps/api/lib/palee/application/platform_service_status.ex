defmodule Palee.Application.PlatformServiceStatus do
  @moduledoc """
  ADR-364: the status page in the platform console (vendors), for
  `PaleeWeb.PlatformStatusController`: the live probe of every component
  with its internal reason, incidents and maintenance with their timeline,
  and the number of subscribers. A new incident or update with `notify`
  queues the email to confirmed subscribers.
  """

  alias Palee.Status
  alias Palee.Workers.StatusNotifyJob

  def console(context), do: Status.console(context, clock().now())

  def create_incident(context, params) do
    with {:ok, incident, update} <- Status.create_incident(context, params, clock().now()) do
      :ok = maybe_notify(update)
      {:ok, incident}
    end
  end

  def add_update(context, id, params) do
    with {:ok, incident, update} <- Status.add_incident_update(context, id, params, clock().now()) do
      :ok = maybe_notify(update)
      {:ok, incident}
    end
  end

  def edit_incident(context, id, params), do: Status.edit_incident(context, id, params)

  defp maybe_notify(%{notify: true, id: id}) do
    if Application.get_env(:palee, :start_oban, true) do
      {:ok, _job} = %{"update_id" => id} |> StatusNotifyJob.new() |> Oban.insert()
    end

    :ok
  end

  defp maybe_notify(_update), do: :ok

  defp clock, do: Application.fetch_env!(:palee, :status_clock)
end
