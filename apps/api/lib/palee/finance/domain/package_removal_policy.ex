defmodule Palee.Finance.Domain.PackageRemovalPolicy do
  @moduledoc """
  ADR-660: the rules of «Αφαίρεση πακέτου» (staff remove a member's package
  completely), kept free of storage.

    * Only a package the member holds now can be removed (`active` or
      `paused`, not already removed).
    * An unpaid invoice of the package that nobody paid anything on: staff
      who manage billing choose each time, with no preselection, whether it
      is voided (`"void"`) or stays owed (`"keep"`). Staff who only take
      payments (front desk) never write a debt off: it always stays.
    * Money paid, and what is left on a partly paid invoice, always stay.
    * Removal is undone within `undo_seconds/0` (the same minute a scan
      check-in can be undone, ADR-155); then it settles: upcoming bookings
      are cancelled and the member is told.
    * A member who left the box kept the package until its last day
      (ADR-595); without it they keep the box until yesterday, or until the
      last day of another package they still hold.
  """

  @undo_seconds 60
  @removable_statuses ["active", "paused"]
  @choices ["void", "keep"]

  def undo_seconds, do: @undo_seconds
  def choices, do: @choices

  @doc "Whether `subscription` can be removed now."
  def removable(%{status: status} = subscription) when status in @removable_statuses do
    if is_nil(Map.get(subscription, :removed_on)),
      do: :ok,
      else: {:error, :subscription_not_removable}
  end

  def removable(_subscription), do: {:error, :subscription_not_removable}

  @doc """
  What happens to the unpaid invoices nobody paid anything on (`untouched`):
  `{:ok, nil}` (there are none), `{:ok, "void" | "keep"}`, or an error when
  the choice is missing (`:invoice_choice_required`), unknown
  (`:invalid_invoice_choice`) or not this person's to make
  (`:write_off_not_allowed`).
  """
  def invoice_choice([], _choice, _may_write_off?), do: {:ok, nil}

  def invoice_choice(_untouched, choice, may_write_off?) do
    cond do
      choice in [nil, ""] and may_write_off? -> {:error, :invoice_choice_required}
      choice in [nil, ""] -> {:ok, "keep"}
      choice not in @choices -> {:error, :invalid_invoice_choice}
      choice == "void" and not may_write_off? -> {:error, :write_off_not_allowed}
      true -> {:ok, choice}
    end
  end

  @doc """
  The member's new last day at the box when they had left it and kept this
  package: yesterday, or the latest last day of the packages they still hold
  (`remaining_last_days`). Nil when nothing changes (they had not left, or
  their last day is already behind them).
  """
  def leaving_on_after(nil, _remaining_last_days, _today), do: nil

  def leaving_on_after(%Date{} = leaving_on, remaining_last_days, %Date{} = today) do
    if Date.compare(leaving_on, today) == :lt do
      nil
    else
      Enum.max([Date.add(today, -1) | remaining_last_days], Date)
      |> then(&if(Date.compare(&1, leaving_on) == :lt, do: &1, else: nil))
    end
  end

  @doc "When the undo closes for a removal made at `now`."
  def undo_until(%DateTime{} = now), do: DateTime.add(now, @undo_seconds, :second)

  @doc "Whether the removal can still be undone at `now`."
  def undoable(%{undone_at: %DateTime{}}, _now), do: {:error, :removal_not_undoable}
  def undoable(%{settled_at: %DateTime{}}, _now), do: {:error, :removal_not_undoable}

  def undoable(%{undo_until: %DateTime{} = until}, %DateTime{} = now) do
    if DateTime.compare(now, until) == :gt, do: {:error, :removal_not_undoable}, else: :ok
  end

  @doc """
  What the removal does at `now`: `:wait` (the undo is still open),
  `:skip` (it was undone, or it has already been settled), or `:settle`.
  """
  def settle_step(%{undone_at: %DateTime{}}, _now), do: :skip
  def settle_step(%{settled_at: %DateTime{}}, _now), do: :skip

  def settle_step(%{undo_until: %DateTime{} = until}, %DateTime{} = now) do
    if DateTime.compare(now, until) == :gt, do: :settle, else: :wait
  end

  @doc "The reason, trimmed to the 500 characters kept, or nil."
  def reason(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 500)
    end
  end

  def reason(_value), do: nil
end
