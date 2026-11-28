defmodule Palee.Finance.Queries.GetFinanceCleanupRecord do
  alias Palee.Finance.FinanceStore

  @doc "ADR-797: one active invoice, receipt or payment with its details, or nil."
  def call(record_type, record_id),
    do: FinanceStore.get_finance_cleanup_record(record_type, record_id)
end
