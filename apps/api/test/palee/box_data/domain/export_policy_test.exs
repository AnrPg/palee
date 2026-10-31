defmodule Palee.BoxData.Domain.ExportPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.BoxData.Domain.ExportPolicy

  @now ~U[2026-11-02 10:00:00Z]

  test "one in progress, one a day; a failed one does not count" do
    assert :ok = ExportPolicy.can_request?([], @now)

    assert {:error, :export_in_progress} =
             ExportPolicy.can_request?([%{status: "pending", requested_at: @now}], @now)

    yesterday_ish = DateTime.add(@now, -23 * 3600)

    assert {:error, :box_export_too_soon} =
             ExportPolicy.can_request?([%{status: "ready", requested_at: yesterday_ish}], @now)

    assert :ok =
             ExportPolicy.can_request?([%{status: "failed", requested_at: yesterday_ish}], @now)

    assert :ok =
             ExportPolicy.can_request?(
               [%{status: "ready", requested_at: DateTime.add(@now, -25 * 3600)}],
               @now
             )
  end

  test "visible status, file name and folder" do
    ready = %{status: "ready", expires_at: DateTime.add(@now, 60)}
    assert ExportPolicy.visible_status(ready, @now) == "ready"
    assert ExportPolicy.visible_status(%{ready | expires_at: @now}, @now) == "expired"
    assert ExportPolicy.file_name("crossfit-x", @now) == "palee-crossfit-x-data-2026-11-02.zip"
    assert ExportPolicy.object_folder("abc") == "exports/box-data/abc/"
  end
end
