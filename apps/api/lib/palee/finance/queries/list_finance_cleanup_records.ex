defmodule Palee.Finance.Queries.ListFinanceCleanupRecords do
  alias Palee.Finance.Domain.CleanupRecordFilter
  alias Palee.Finance.FinanceStore

  @doc "ADR-797: one page of active records for «Εκκαθάριση συναλλαγών»."
  def call(%CleanupRecordFilter{} = filter), do: FinanceStore.list_finance_cleanup_records(filter)
  def call(params), do: params |> CleanupRecordFilter.new() |> call()
end
