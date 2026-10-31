defmodule Palee.Status.Domain.Overview do
  @moduledoc """
  What the status page says right now (ADR-364), from the latest probe of
  each component and the incidents and maintenance that are active.

  A component's public status:

  * `maintenance` while an active maintenance names it (planned downtime is
    not an outage);
  * otherwise the worse of its probe and the active incidents that name it
    (`minor` impact → `degraded`, `major`/`critical` → `down`);
  * `unknown` when no probe ran in the last `stale_after_seconds` and no
    incident names it (the probe itself is not running: the page must not
    claim all is well).

  The overall status: `major_outage` (a `critical` incident, or the app is
  down), `partial_outage` (some component down), `degraded`, `maintenance`,
  `unknown` (no fresh probe at all) or `operational`.

  Pure: callers pass `now`.
  """

  alias Palee.Status.Domain.{Components, IncidentPolicy}

  @stale_after_seconds 300

  def stale_after_seconds, do: @stale_after_seconds

  @doc """
  `%{status, components: [%{key, status, checked_at}]}` from the component
  states (`%{component, status, checked_at}`) and the incidents active at
  `now`.
  """
  def build(states, incidents, %DateTime{} = now) do
    by_key = Map.new(states, &{&1.component, &1})
    active = Enum.filter(incidents, &IncidentPolicy.active?(&1, now))

    components =
      Enum.map(Components.all(), fn key ->
        state = Map.get(by_key, key)

        %{
          key: key,
          status: component_status(key, state, active, now),
          checked_at: state && state.checked_at
        }
      end)

    %{status: overall(components, active), components: components}
  end

  defp component_status(key, state, active, now) do
    touching = Enum.filter(active, &(key in &1.components))

    if Enum.any?(touching, &(&1.kind == "maintenance")) do
      "maintenance"
    else
      probe = probe_status(state, now)

      touching
      |> Enum.map(&impact_status(&1.impact))
      |> Enum.reduce(probe, &worse/2)
    end
  end

  defp probe_status(nil, _now), do: "unknown"

  defp probe_status(%{status: status, checked_at: checked_at}, now) do
    if DateTime.diff(now, checked_at) > @stale_after_seconds, do: "unknown", else: status
  end

  defp impact_status("minor"), do: "degraded"
  defp impact_status(impact) when impact in ["major", "critical"], do: "down"
  defp impact_status(_none), do: "operational"

  # "unknown" gives way to anything an incident says about the component.
  defp worse("operational", "unknown"), do: "unknown"
  defp worse(status, "unknown"), do: status
  defp worse("unknown", status), do: status
  defp worse(a, b), do: Components.worst(a, b)

  defp overall(components, active) do
    statuses = Enum.map(components, & &1.status)
    app = Enum.find(components, &(&1.key == "app"))

    cond do
      Enum.any?(active, &(&1.kind == "incident" and &1.impact == "critical")) -> "major_outage"
      app.status == "down" -> "major_outage"
      "down" in statuses -> "partial_outage"
      "degraded" in statuses -> "degraded"
      "maintenance" in statuses -> "maintenance"
      Enum.all?(statuses, &(&1 == "unknown")) -> "unknown"
      true -> "operational"
    end
  end
end
