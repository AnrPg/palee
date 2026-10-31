defmodule Palee.BoxData.Domain.CsvBundleTest do
  use ExUnit.Case, async: true

  alias Palee.BoxData.Domain.CsvBundle

  @bom <<0xEF, 0xBB, 0xBF>>

  test "cells: quoting, JSON for nested values, formula guard" do
    assert CsvBundle.cell(nil) == ""
    assert CsvBundle.cell(42) == "42"
    assert CsvBundle.cell(true) == "true"
    assert CsvBundle.cell("Γιώργος") == "Γιώργος"
    assert CsvBundle.cell("a,b") == ~s("a,b")
    assert CsvBundle.cell(~s(say "hi")) == ~s("say ""hi""")
    assert CsvBundle.cell("line\nbreak") == ~s("line\nbreak")
    assert CsvBundle.cell(%{"a" => 1}) == ~s("{""a"":1}")
    assert CsvBundle.cell("=HYPERLINK(1)") == "'=HYPERLINK(1)"
    assert CsvBundle.cell("-5 kg") == "'-5 kg"
    assert CsvBundle.cell(-5) == "-5"
  end

  test "a table is BOM + sorted header + rows with CRLF" do
    csv = CsvBundle.csv([%{"b" => 2, "a" => "x"}, %{"a" => "y", "c" => nil}])
    assert csv == @bom <> "a,b,c\r\nx,2,\r\ny,,\r\n"
  end

  test "build/1 makes a ZIP with the manifest, a readme and one CSV per table" do
    {:ok, bundle} =
      CsvBundle.build(%{
        organization: %{"id" => "org", "slug" => "crossfit-x", "name" => "CrossFit X"},
        generated_at: ~U[2026-11-02 10:00:00Z],
        sections: [
          %{context: "finance", tables: %{"finance_invoices" => [%{"id" => 1}, %{"id" => 2}]}},
          %{context: "scheduling", tables: %{"bookings" => [], "class_types" => [%{"id" => 3}]}}
        ]
      })

    assert bundle.record_count == 3
    assert bundle.table_count == 3

    {:ok, files} = :zip.unzip(bundle.zip, [:memory])
    files = Map.new(files, fn {name, body} -> {to_string(name), body} end)

    assert Map.keys(files) |> Enum.sort() == [
             "README.txt",
             "finance/finance_invoices.csv",
             "manifest.json",
             "scheduling/bookings.csv",
             "scheduling/class_types.csv"
           ]

    manifest = Jason.decode!(files["manifest.json"])
    assert manifest["format"] == "palee-box-export/v1"
    assert %{"file" => "finance/finance_invoices.csv", "rows" => 2} in manifest["files"]
    assert files["scheduling/bookings.csv"] == @bom <> "\r\n"
    assert files["README.txt"] =~ "CrossFit X"
  end
end
