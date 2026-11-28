defmodule Palee.Finance.Domain.CleanupRecordFilterTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.CleanupRecordFilter

  @id "7b0f2c0e-2f61-4a5b-9a51-0c1d2e3f4a5b"

  test "reads valid filters and drops invalid ones" do
    filter =
      CleanupRecordFilter.new(%{
        "q" => "  Μαρία ",
        "user_id" => @id,
        "package_id" => "not-a-uuid",
        "from" => "2026-11-01",
        "to" => "30/11/2026",
        "kind" => "receipt",
        "limit" => "500"
      })

    assert filter.q == "Μαρία"
    assert filter.user_id == @id
    assert filter.package_id == nil
    assert filter.from == ~D[2026-11-01]
    assert filter.to == nil
    assert filter.kind == "receipt"
    assert filter.limit == 100
    assert CleanupRecordFilter.new(%{"kind" => "transfer", "q" => "  "}).kind == nil
    assert CleanupRecordFilter.new(%{"q" => "  "}).q == nil
    assert CleanupRecordFilter.new(nil).limit == 30
  end

  test "a kind keeps only the table that can match it" do
    assert CleanupRecordFilter.wants?(CleanupRecordFilter.new(%{}), :payment)
    assert CleanupRecordFilter.wants?(CleanupRecordFilter.new(%{"kind" => "payment"}), :payment)
    refute CleanupRecordFilter.wants?(CleanupRecordFilter.new(%{"kind" => "payment"}), :document)
    assert CleanupRecordFilter.wants?(CleanupRecordFilter.new(%{"kind" => "invoice"}), :document)
    refute CleanupRecordFilter.wants?(CleanupRecordFilter.new(%{"kind" => "receipt"}), :payment)
  end

  test "the cursor round-trips and a broken one is ignored" do
    at = ~U[2026-11-28 10:15:30.123456Z]
    cursor = CleanupRecordFilter.encode_cursor(at, @id)

    assert CleanupRecordFilter.decode_cursor(cursor) == {at, @id}
    assert CleanupRecordFilter.new(%{"cursor" => cursor}).cursor == {at, @id}
    assert CleanupRecordFilter.decode_cursor("%%%") == nil
    assert CleanupRecordFilter.decode_cursor(Base.url_encode64("x|y", padding: false)) == nil
  end

  test "pages merge both tables newest first and point at the last record" do
    filter = CleanupRecordFilter.new(%{"limit" => "2"})
    same = ~U[2026-11-28 10:00:00.000000Z]

    rows = [
      %{id: "a", inserted_at: ~U[2026-11-27 10:00:00.000000Z]},
      %{id: "b", inserted_at: same},
      %{id: "c", inserted_at: same}
    ]

    page = CleanupRecordFilter.page(filter, rows)

    assert Enum.map(page.records, & &1.id) == ["c", "b"]
    assert page.next_cursor == CleanupRecordFilter.encode_cursor(same, "b")
    assert CleanupRecordFilter.page(filter, Enum.take(rows, 2)).next_cursor == nil
  end
end
