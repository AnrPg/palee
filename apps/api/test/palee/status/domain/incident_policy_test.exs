defmodule Palee.Status.Domain.IncidentPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Status.Domain.IncidentPolicy

  @now ~U[2026-11-02 10:00:00.000000Z]

  describe "validate_new/2" do
    test "an incident starts investigating, major, now, with its first note" do
      assert {:ok, attrs} =
               IncidentPolicy.validate_new(
                 %{
                   "title" => "  Bookings are slow  ",
                   "components" => ["payments", "app", "app"],
                   "body" => "We are looking into it."
                 },
                 @now
               )

      assert attrs.kind == "incident"
      assert attrs.status == "investigating"
      assert attrs.impact == "major"
      assert attrs.title == "Bookings are slow"
      assert attrs.components == ["app", "payments"]
      assert attrs.started_at == @now
      assert attrs.resolved_at == nil

      # ADR-366: no language given, no English copy.
      assert attrs.update == %{
               status: "investigating",
               body: "We are looking into it.",
               notify: true,
               locale: nil,
               body_en: nil,
               en_source: nil
             }
    end

    test "a maintenance needs a window and starts when the window starts" do
      params = %{
        kind: "maintenance",
        title: "Database upgrade",
        body: "About ten minutes.",
        scheduled_for: "2026-11-03T02:00:00Z",
        scheduled_until: "2026-11-03T02:30:00Z",
        notify: false
      }

      assert {:ok, attrs} = IncidentPolicy.validate_new(params, @now)
      assert attrs.status == "scheduled"
      assert attrs.impact == "minor"
      assert attrs.started_at == ~U[2026-11-03 02:00:00Z]
      refute attrs.update.notify

      assert {:error, :invalid_maintenance_window} =
               IncidentPolicy.validate_new(Map.delete(params, :scheduled_until), @now)

      assert {:error, :invalid_maintenance_window} =
               IncidentPolicy.validate_new(
                 %{params | scheduled_until: "2026-11-03T01:00:00Z"},
                 @now
               )
    end

    test "refuses bad input" do
      base = %{"title" => "Slow", "body" => "Note"}

      assert {:error, :invalid_status_kind} =
               IncidentPolicy.validate_new(Map.put(base, "kind", "x"), @now)

      assert {:error, :invalid_status_title} =
               IncidentPolicy.validate_new(%{base | "title" => "ab"}, @now)

      assert {:error, :invalid_status_impact} =
               IncidentPolicy.validate_new(Map.put(base, "impact", "huge"), @now)

      assert {:error, :unknown_status_component} =
               IncidentPolicy.validate_new(Map.put(base, "components", ["kitchen"]), @now)

      assert {:error, :invalid_status_transition} =
               IncidentPolicy.validate_new(Map.put(base, "status", "scheduled"), @now)

      assert {:error, :invalid_status_note} =
               IncidentPolicy.validate_new(%{base | "body" => " "}, @now)
    end

    test "an incident published already resolved is closed at once" do
      assert {:ok, %{resolved_at: @now, status: "resolved"}} =
               IncidentPolicy.validate_new(
                 %{"title" => "Short blip", "body" => "Fixed", "status" => "resolved"},
                 @now
               )
    end
  end

  describe "validate_update/3" do
    test "moves an open incident and closes it on resolved" do
      incident = %{kind: "incident", status: "investigating"}

      assert {:ok, %{status: "monitoring", resolved_at: nil}} =
               IncidentPolicy.validate_update(
                 incident,
                 %{status: "monitoring", body: "Fix out"},
                 @now
               )

      assert {:ok, %{status: "resolved", resolved_at: @now, notify: true}} =
               IncidentPolicy.validate_update(incident, %{status: "resolved", body: "Done"}, @now)
    end

    test "a closed incident takes no more steps; statuses must fit the kind" do
      assert {:error, :status_incident_closed} =
               IncidentPolicy.validate_update(
                 %{kind: "incident", status: "resolved"},
                 %{body: "x"},
                 @now
               )

      assert {:error, :invalid_status_transition} =
               IncidentPolicy.validate_update(
                 %{kind: "incident", status: "identified"},
                 %{status: "in_progress", body: "x"},
                 @now
               )
    end

    test "a maintenance that starts records when it started" do
      assert {:ok, %{started_at: @now}} =
               IncidentPolicy.validate_update(
                 %{kind: "maintenance", status: "scheduled"},
                 %{status: "in_progress", body: "Started"},
                 @now
               )
    end
  end

  test "validate_edit/1 keeps only the given fields" do
    assert {:ok, %{impact: "critical"}} = IncidentPolicy.validate_edit(%{impact: "critical"})
    assert {:ok, %{}} = IncidentPolicy.validate_edit(%{})
    assert {:error, :invalid_status_title} = IncidentPolicy.validate_edit(%{title: ""})
  end

  test "active?/2 and upcoming?/2" do
    window = %{
      kind: "maintenance",
      status: "scheduled",
      scheduled_for: ~U[2026-11-02 09:00:00Z],
      scheduled_until: ~U[2026-11-02 11:00:00Z]
    }

    assert IncidentPolicy.active?(window, @now)
    refute IncidentPolicy.upcoming?(window, @now)

    later = %{
      window
      | scheduled_for: ~U[2026-11-03 09:00:00Z],
        scheduled_until: ~U[2026-11-03 10:00:00Z]
    }

    refute IncidentPolicy.active?(later, @now)
    assert IncidentPolicy.upcoming?(later, @now)

    assert IncidentPolicy.active?(%{kind: "incident", status: "monitoring"}, @now)
    refute IncidentPolicy.active?(%{kind: "incident", status: "resolved"}, @now)
  end
end
