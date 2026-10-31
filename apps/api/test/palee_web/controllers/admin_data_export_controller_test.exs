defmodule PaleeWeb.AdminDataExportControllerTest do
  @moduledoc """
  ADR-365 (CP-G5) over HTTP: an owner asks for a copy of all the box's data
  and downloads one ZIP of CSV files (in tests built at once, without Oban).
  It holds the box's tables, never another box's rows, never members'
  personal tables, never secrets. Staff who are not owners cannot ask.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TenantPurgeFixtures
  import Palee.TestFixtures

  alias Palee.Infrastructure.Security.MemoryRateLimiter
  alias Palee.Organizations
  alias Palee.TestSupport.MemoryObjectStore

  setup do
    MemoryRateLimiter.reset!()
    box = seed_tenant("Export Box")
    other = seed_tenant("Other Box")
    %{box: box, other: other}
  end

  defp path(box), do: "/api/org/#{box.organization.slug}/admin/data-exports"

  defp unzip(key) do
    {:ok, zip} = MemoryObjectStore.get(:documents, key)
    {:ok, files} = :zip.unzip(zip, [:memory])
    Map.new(files, fn {name, body} -> {to_string(name), body} end)
  end

  test "an owner gets every box table as CSV, once a day", %{conn: conn, box: box, other: other} do
    export =
      conn |> put_bearer_token(box.owner) |> post(path(box)) |> json_response(202)

    assert export["status"] == "ready"
    assert export["record_count"] > 0
    assert %{"name" => name, "download_url" => url, "sha256" => sha} = export["file"]
    assert name =~ ~r/^palee-.+-data-\d{4}-\d{2}-\d{2}\.zip$/
    assert is_binary(url)
    assert byte_size(sha) == 64

    %{"exports" => [listed]} =
      conn |> recycle() |> put_bearer_token(box.owner) |> get(path(box)) |> json_response(200)

    assert listed["id"] == export["id"]

    {:ok, [%{key: stored_key}]} =
      MemoryObjectStore.list_objects(
        :documents,
        "organizations/#{box.organization.id}/exports/box-data/#{export["id"]}/"
      )

    files = unzip(stored_key)
    assert Map.has_key?(files, "manifest.json")
    assert files["finance/finance_invoices.csv"] =~ box.organization.id
    assert files["finance/finance_invoice_lines.csv"] =~ "Export Box monthly"
    refute files["finance/finance_invoice_lines.csv"] =~ "Other Box monthly"
    refute Enum.any?(files, fn {_name, body} -> body =~ other.organization.id end)

    # Members' personal tables stay theirs; secret columns never leave.
    assert files["pantheon/user_pr_records.csv"] in [nil, <<0xEF, 0xBB, 0xBF, "\r\n">>]
    refute Enum.any?(files, fn {_name, body} -> body =~ "token_digest" end)
    refute Enum.any?(files, fn {_name, body} -> body =~ "credentials" end)

    assert %{"code" => "box_export_too_soon"} =
             conn |> recycle() |> put_bearer_token(box.owner) |> post(path(box)) |> json_response(409)
  end

  test "staff without the owner's right and members cannot ask", %{conn: conn, box: box} do
    coach = user_fixture()

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: box.organization.id,
        user_id: coach.id,
        role: :coach,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    for user <- [coach, box.member] do
      status = conn |> recycle() |> put_bearer_token(user) |> post(path(box)) |> Map.get(:status)
      assert status in [403, 404]
    end
  end
end
