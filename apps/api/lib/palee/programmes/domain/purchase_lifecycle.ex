defmodule Palee.Programmes.Domain.PurchaseLifecycle do
  @moduledoc """
  One buyer's purchase of a programme version (ADR-371), pure.

      pending_payment ─paid──► active ─► completed (after the last day)
             │                    ├─► withdrawn (the buyer, ADR-371 rules)
             └─► cancelled        └─► refunded (staff refunded it in full)

  Nothing is delivered before the provider confirms the money. A buyer
  holds at most one open purchase (pending or active) of one programme.
  """

  @statuses ~w(pending_payment active completed withdrawn refunded cancelled)
  @open ~w(pending_payment active)
  @owned ~w(active completed)

  def statuses, do: @statuses
  def open_statuses, do: @open
  def owned_statuses, do: @owned

  @doc "A lifecycle step: `{:ok, changes}` or `{:error, :invalid_purchase_transition}`."
  def transition(%{status: "pending_payment"}, {:paid, payment}, now),
    do:
      {:ok,
       %{
         status: "active",
         activated_at: now,
         finance_payment_id: payment[:finance_payment_id],
         fiscal_document_id: payment[:fiscal_document_id]
       }}

  def transition(%{status: "pending_payment"}, :cancel, now),
    do: {:ok, %{status: "cancelled", ended_at: now, end_reason: "cancelled"}}

  def transition(%{status: "active"}, :complete, now),
    do: {:ok, %{status: "completed", ended_at: now, end_reason: "completed"}}

  def transition(%{status: "active"} = purchase, {:refunded, cents, :withdrawal}, now),
    do:
      {:ok,
       %{
         status: "withdrawn",
         refunded_cents: (purchase.refunded_cents || 0) + cents,
         ended_at: now,
         end_reason: "withdrawn"
       }}

  def transition(%{status: status} = purchase, {:refunded, cents, :staff}, now)
      when status in @owned do
    refunded = (purchase.refunded_cents || 0) + cents

    if refunded >= purchase.price_cents,
      do:
        {:ok,
         %{status: "refunded", refunded_cents: refunded, ended_at: now, end_reason: "refunded"}},
      else: {:ok, %{refunded_cents: refunded}}
  end

  def transition(_purchase, _step, _now), do: {:error, :invalid_purchase_transition}

  @doc "Whether the purchase still gives its WODs (removing the future ones otherwise)."
  def delivering?(%{status: "active"}), do: true
  def delivering?(_purchase), do: false

  @doc "Whether the buyer owns (or owned) the programme: may open its WODs and review it."
  def owned?(%{status: status}), do: status in @owned
end
