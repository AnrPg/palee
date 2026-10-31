defmodule PaleeWeb.ServiceStatusJSON do
  @moduledoc "JSON views of the status page (ADR-364). Probe reasons only in the console."

  def overview(view) do
    %{
      status: view.status,
      components: Enum.map(view.components, &component/1),
      active: Enum.map(view.active, &incident/1),
      upcoming: Enum.map(view.upcoming, &incident/1),
      generated_at: view.generated_at
    }
  end

  def history(view) do
    %{
      days: view.days,
      from: view.from,
      to: view.to,
      components: view.components,
      incidents: Enum.map(view.incidents, &incident/1),
      generated_at: view.generated_at
    }
  end

  def console(view) do
    %{
      probes:
        Enum.map(view.states, fn state ->
          %{
            key: state.component,
            status: state.status,
            reason: state.reason,
            checked_at: state.checked_at,
            changed_at: state.changed_at
          }
        end),
      incidents: Enum.map(view.incidents, &incident/1),
      subscribers: view.subscribers
    }
  end

  def incident(incident) do
    %{
      id: incident.id,
      kind: incident.kind,
      title: incident.title,
      impact: incident.impact,
      status: incident.status,
      components: incident.components,
      scheduled_for: incident.scheduled_for,
      scheduled_until: incident.scheduled_until,
      started_at: incident.started_at,
      resolved_at: incident.resolved_at,
      updates:
        incident.updates
        |> List.wrap()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        |> Enum.map(fn update ->
          %{
            id: update.id,
            status: update.status,
            body: update.body,
            created_at: update.inserted_at
          }
        end)
    }
  end

  defp component(component),
    do: %{key: component.key, status: component.status, checked_at: component.checked_at}
end
