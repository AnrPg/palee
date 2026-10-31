defmodule Palee.Application.BoxDataExportRLSTest do
  @moduledoc """
  ADR-365 under real row-level security: the owner's export runs as the
  non-superuser runtime role and reads only the owner's box.
  """

  use Palee.DataCase, async: false

  import Palee.TenantPurgeFixtures

  alias Palee.Application.BoxDataExports
  alias Palee.{Organizations, RLSCase}
  alias Palee.TestSupport.MemoryObjectStore

  test "the export is built as the runtime role with the box's rows only" do
    RLSCase.ensure_runtime_role!()
    box = seed_tenant("RLS Export Box")
    _other = seed_tenant("RLS Neighbour Box")

    Repo.query!("SET LOCAL ROLE #{RLSCase.runtime_role()}")
    {:ok, context} = Organizations.resolve_tenant_context(box.owner, box.organization.slug)

    assert {:ok, %{status: "ready", file: %{name: name}} = export} =
             BoxDataExports.request(context)

    assert export.record_count > 0

    {:ok, [%{key: key}]} =
      MemoryObjectStore.list_objects(
        :documents,
        "organizations/#{box.organization.id}/exports/box-data/#{export.id}/" <> name
      )

    {:ok, zip} = MemoryObjectStore.get(:documents, key)
    {:ok, files} = :zip.unzip(zip, [:memory])
    files = Map.new(files, fn {file, body} -> {to_string(file), body} end)

    assert files["finance/finance_invoices.csv"] =~ box.organization.id
    assert files["finance/finance_invoice_lines.csv"] =~ "RLS Export Box monthly"
    refute files["finance/finance_invoice_lines.csv"] =~ "RLS Neighbour Box"
  end
end
