defmodule PaleeWeb.AdminDataExportControllerTest do
  @moduledoc """
  ADR-365 (CP-G5) over HTTP: an owner asks for a copy of all the box's data
  and downloads one ZIP of CSV files (in tests built at once, without Oban).
  It holds the box's tables, never another box's rows, never members'
  personal tables, never secrets. Staff who are not owners cannot ask.
  """

  use PaleeWeb.ConnCase, async: false
  use Palee.EmailCase

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

    {:ok, stored} =
      MemoryObjectStore.list_objects(
        :documents,
        "organizations/#{box.organization.id}/exports/box-data/#{export["id"]}/"
      )

    # ADR-367: the box's stored files come in their own ZIP parts.
    assert [%{key: stored_key}] = Enum.reject(stored, &(&1.key =~ "-files-"))

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
             conn
             |> recycle()
             |> put_bearer_token(box.owner)
             |> post(path(box))
             |> json_response(409)
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

  # ADR-367: photos and PDFs go in ZIP parts; one email when it is ready.
  test "stored files come in parts next to the CSV ZIP, and the owner gets one email", %{
    conn: conn,
    box: box,
    other: other
  } do
    previous = Application.get_env(:palee, :box_data_export)
    Application.put_env(:palee, :box_data_export, part_bytes: 20)
    on_exit(fn -> Application.put_env(:palee, :box_data_export, previous || []) end)

    prefix = "organizations/#{box.organization.id}/"

    :ok =
      MemoryObjectStore.put_object(
        :documents,
        prefix <> "documents/contract.pdf",
        "%PDF-contract",
        "application/pdf"
      )

    :ok =
      MemoryObjectStore.put_object(:branding, prefix <> "branding/logo.png", "logo", "image/png")

    :ok =
      MemoryObjectStore.put_object(
        :media_public,
        prefix <> "media/p1/photo.jpg",
        "photo",
        "image/jpeg"
      )

    :ok =
      MemoryObjectStore.put_object(
        :documents,
        "organizations/#{other.organization.id}/documents/x.pdf",
        "%PDF-other",
        "application/pdf"
      )

    export = conn |> put_bearer_token(box.owner) |> post(path(box)) |> json_response(202)

    assert export["status"] == "ready"
    # The fixture box stores a few files of its own; parts stay under 20 bytes
    # of content each unless one file is bigger.
    assert [first | _] = parts = export["parts"]
    assert length(parts) >= 2
    assert first["name"] =~ ~r/^palee-.+-files-\d{4}-\d{2}-\d{2}-1\.zip$/
    assert Enum.sum(Enum.map(parts, & &1["files"])) >= 3
    assert Enum.all?(parts, &is_binary(&1["download_url"]))

    {:ok, stored} =
      MemoryObjectStore.list_objects(:documents, prefix <> "exports/box-data/#{export["id"]}/")

    entries =
      stored
      |> Enum.filter(&(&1.key =~ "-files-"))
      |> Enum.flat_map(fn %{key: key} -> key |> unzip() |> Map.to_list() end)
      |> Map.new()

    assert entries["documents/documents/contract.pdf"] == "%PDF-contract"
    assert entries["branding/branding/logo.png"] == "logo"
    assert entries["media/media/p1/photo.jpg"] == "photo"
    refute Enum.any?(entries, fn {_name, body} -> body == "%PDF-other" end)

    notice = assert_email_enqueued(kind: :box_data_export_ready, to: box.owner.email)
    assert notice.text =~ "/org/#{box.organization.slug}/admin/settings#organization"
    refute notice.text =~ "objects.test"
  end
end
