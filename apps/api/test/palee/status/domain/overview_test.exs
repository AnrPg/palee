defmodule Palee.Status.Domain.OverviewTest do
  use ExUnit.Case, async: true

  alias Palee.Status.Domain.Overview

  @now ~U[2026-11-02 10:00:00Z]

  defp states(overrides \\ %{}) do
    for key <- ~w(app search files email payments fiscal) do
      %{component: key, status: Map.get(overrides, key, "operational"), checked_at: @now}
    end
  end

  defp status_of(result, key), do: Enum.find(result.components, &(&1.key == key)).status

  test "all fresh and operational" do
    result = Overview.build(states(), [], @now)
    assert result.status == "operational"
    assert Enum.all?(result.components, &(&1.status == "operational"))
  end

  test "a component down is a partial outage; the app down is a major outage" do
    assert Overview.build(states(%{"search" => "down"}), [], @now).status == "partial_outage"
    assert Overview.build(states(%{"app" => "down"}), [], @now).status == "major_outage"
    assert Overview.build(states(%{"email" => "degraded"}), [], @now).status == "degraded"
  end

  test "stale or missing probes are unknown, never operational" do
    stale = Enum.map(states(), &%{&1 | checked_at: DateTime.add(@now, -600)})
    result = Overview.build(stale, [], @now)
    assert result.status == "unknown"
    assert status_of(Overview.build([], [], @now), "fiscal") == "unknown"
  end

  test "incidents raise a component's status; a critical one is a major outage" do
    incident = %{
      kind: "incident",
      status: "identified",
      impact: "minor",
      components: ["payments"]
    }

    result = Overview.build(states(), [incident], @now)
    assert status_of(result, "payments") == "degraded"
    assert result.status == "degraded"

    critical = %{incident | impact: "critical", components: []}
    assert Overview.build(states(), [critical], @now).status == "major_outage"

    resolved = %{incident | status: "resolved", impact: "major"}
    assert Overview.build(states(), [resolved], @now).status == "operational"
  end

  test "active maintenance shows as maintenance, not as an outage" do
    maintenance = %{
      kind: "maintenance",
      status: "in_progress",
      impact: "major",
      components: ["app"]
    }

    result = Overview.build(states(%{"app" => "down"}), [maintenance], @now)
    assert status_of(result, "app") == "maintenance"
    assert result.status == "maintenance"
  end
end
