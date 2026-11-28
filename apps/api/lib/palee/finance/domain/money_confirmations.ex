defmodule Palee.Finance.Domain.MoneyConfirmations do
  @moduledoc """
  ADR-795: the questions «Έλαβες πραγματικά τα χρήματα;» that staff may
  choose not to see again until the box's midnight («Να μην εμφανιστεί ξανά
  σήμερα»). Only these are skippable: every other confirmation (a debt
  forgiven, a class cancelled, a role changed…) is asked every time.

    * `record_payment`: «Καταγραφή πληρωμής» (cash, POS, transfer, other);
    * `desk_collect`: «Εισπράχθηκαν» / «Είσπραξη» on a «Το θέλω»;
    * `shop_pickup`: handing over an e-shop order paid at the desk;
    * `cash_refund`: money given back in cash.
  """

  @kinds ~w(record_payment desk_collect shop_pickup cash_refund)

  def kinds, do: @kinds

  def kind?(kind), do: kind in @kinds
end
