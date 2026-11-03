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
      incidents: Enum.map(view.incidents, &incident(&1, Map.get(view, :publishers, %{}))),
      subscribers: view.subscribers
    }
  end

  @doc "An incident; with `publishers` (console only) each part says who published it (ADR-366)."
  def incident(incident, publishers) when is_map(publishers) do
    incident
    |> incident()
    |> Map.put(:published_by, publisher(publishers, incident.created_by_id))
    |> Map.update!(:updates, fn updates ->
      authors = Map.new(List.wrap(incident.updates), &{&1.id, &1.created_by_id})

      Enum.map(updates, &Map.put(&1, :published_by, publisher(publishers, authors[&1.id])))
    end)
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
      locale: incident.locale,
      title_en: incident.title_en,
      en_source: incident.en_source,
      updates:
        incident.updates
        |> List.wrap()
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        |> Enum.map(fn update ->
          %{
            id: update.id,
            status: update.status,
            body: update.body,
            locale: update.locale,
            body_en: update.body_en,
            en_source: update.en_source,
            created_at: update.inserted_at
          }
        end)
    }
  end

  def translation(answer), do: %{locale: answer.locale, title: answer.title, body: answer.body}

  defp publisher(_publishers, nil), do: nil
  defp publisher(publishers, id), do: Map.get(publishers, id)

  defp component(component),
    do: %{key: component.key, status: component.status, checked_at: component.checked_at}
end
