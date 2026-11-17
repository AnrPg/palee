defmodule Palee.Finance.Domain.PackageRemovalPolicyTest do
  # ADR-660: the rules of «Αφαίρεση πακέτου».
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.PackageRemovalPolicy, as: Policy

  @today ~D[2026-11-17]
  @now ~U[2026-11-17 10:00:00Z]

  test "only a package held now can be removed" do
    assert :ok = Policy.removable(%{status: "active", removed_on: nil})
    assert :ok = Policy.removable(%{status: "paused", removed_on: nil})
    assert {:error, :subscription_not_removable} = Policy.removable(%{status: "expired"})

    assert {:error, :subscription_not_removable} =
             Policy.removable(%{status: "cancelled", removed_on: @today})
  end

  test "an untouched unpaid invoice: billing staff must choose, the front desk always keeps it" do
    invoices = [%{id: "i1"}]

    assert {:ok, nil} = Policy.invoice_choice([], nil, true)
    assert {:ok, nil} = Policy.invoice_choice([], "void", false)
    assert {:error, :invoice_choice_required} = Policy.invoice_choice(invoices, nil, true)
    assert {:ok, "void"} = Policy.invoice_choice(invoices, "void", true)
    assert {:ok, "keep"} = Policy.invoice_choice(invoices, "keep", true)
    assert {:error, :invalid_invoice_choice} = Policy.invoice_choice(invoices, "maybe", true)
    assert {:ok, "keep"} = Policy.invoice_choice(invoices, nil, false)
    assert {:ok, "keep"} = Policy.invoice_choice(invoices, "keep", false)
    assert {:error, :write_off_not_allowed} = Policy.invoice_choice(invoices, "void", false)
  end

  test "someone who left keeps the box until yesterday or another package's last day" do
    assert Policy.leaving_on_after(nil, [], @today) == nil
    assert Policy.leaving_on_after(~D[2026-11-28], [], @today) == ~D[2026-11-16]
    assert Policy.leaving_on_after(~D[2026-11-28], [~D[2026-11-20]], @today) == ~D[2026-11-20]
    # Another package lasts as long: nothing changes.
    assert Policy.leaving_on_after(~D[2026-11-28], [~D[2026-11-28]], @today) == nil
    # Their last day is already behind them.
    assert Policy.leaving_on_after(~D[2026-11-10], [], @today) == nil
  end

  test "a minute of undo, then the removal settles once" do
    until = Policy.undo_until(@now)
    assert DateTime.diff(until, @now) == Policy.undo_seconds()

    open = %{undo_until: until, undone_at: nil, settled_at: nil}
    assert :ok = Policy.undoable(open, @now)
    assert {:error, :removal_not_undoable} = Policy.undoable(open, DateTime.add(until, 1))
    assert {:error, :removal_not_undoable} = Policy.undoable(%{open | undone_at: @now}, @now)
    assert {:error, :removal_not_undoable} = Policy.undoable(%{open | settled_at: @now}, @now)

    assert :wait = Policy.settle_step(open, @now)
    assert :settle = Policy.settle_step(open, DateTime.add(until, 1))
    assert :skip = Policy.settle_step(%{open | undone_at: @now}, DateTime.add(until, 1))
    assert :skip = Policy.settle_step(%{open | settled_at: @now}, DateTime.add(until, 1))
  end

  test "the reason is trimmed and kept to 500 characters" do
    assert Policy.reason("  ") == nil
    assert Policy.reason(nil) == nil
    assert Policy.reason(" Moved away ") == "Moved away"
    assert String.length(Policy.reason(String.duplicate("a", 600))) == 500
  end
end
