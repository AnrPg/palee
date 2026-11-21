defmodule Palee.Finance.Commands.ReopenEntitlementSource do
  @moduledoc """
  Undoes one finalize of a source's reservation (staff took back «Ήρθε»):
  the visit is held again, so a later cancellation still returns it. Only
  the finalize written under `params.idempotency_key` is undone; a source
  finalized some other way stays as it is.
  """

  alias Palee.Finance.FinanceStore

  def call(user_id, source_context, source_id, allowance, params),
    do:
      FinanceStore.transition_entitlement_source(
        user_id,
        source_context,
        source_id,
        allowance,
        :reopen,
        params
      )
end
