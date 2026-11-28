defmodule Palee.Application.ListFinanceCleanupRecords do
  @moduledoc """
  ADR-797: «Εκκαθάριση συναλλαγών». Lists the business's active invoices,
  receipts and payments with filters (`Palee.Finance.Domain.CleanupRecordFilter`)
  and loads one record for the side panel.

  Finance owns the records and Identity owns the people, so this is where
  they meet: the free text is matched against the names, @handles and
  emails of the business's own customers (never the whole platform), and
  each record gets its customer's name and email.
  """

  alias Palee.{Finance, Identity}
  alias Palee.Finance.Domain.CleanupRecordFilter
  alias Palee.Identity.Domain.NameSearch

  def call(context, params \\ %{}) do
    filter =
      params
      |> CleanupRecordFilter.new()
      |> with_matching_customers(context)

    page = Finance.list_finance_cleanup_records(context, filter)
    people = people_by_id(Enum.map(page.records, & &1.user_id))

    {:ok,
     %{
       records: Enum.map(page.records, &with_customer(&1, people)),
       next_cursor: page.next_cursor
     }}
  end

  @doc "One active record with its details for the side panel."
  def get(context, record_type, record_id) do
    case Finance.get_finance_cleanup_record(context, record_type, record_id) do
      nil ->
        {:error, :not_found}

      record ->
        people = people_by_id([record.user_id, record[:created_by_id]])

        record =
          record
          |> with_customer(people)
          |> Map.put(:created_by_name, name_of(people, record[:created_by_id]))
          |> with_balance_due(context)

        {:ok, %{record: record}}
    end
  end

  @doc """
  The «Πακέτο συνδρομής» filter options: every package, inactive ones too
  (old records may belong to them), active first, then by name.
  """
  def packages(context) do
    packages =
      context
      |> Finance.list_packages()
      |> Enum.map(&%{id: &1.id, name: &1.name || &1.code, active: &1.active != false})
      |> Enum.sort_by(&{not &1.active, String.downcase(&1.name || "")})

    {:ok, %{packages: packages}}
  end

  defp with_matching_customers(%CleanupRecordFilter{q: nil} = filter, _context), do: filter

  defp with_matching_customers(%CleanupRecordFilter{q: text} = filter, context) do
    email_query = String.downcase(text)

    ids =
      context
      |> Finance.list_finance_customer_ids()
      |> Identity.list_by_ids()
      |> Enum.filter(fn person ->
        NameSearch.matches?(person, text) or
          String.contains?(String.downcase(person.email || ""), email_query)
      end)
      |> Enum.map(& &1.id)

    CleanupRecordFilter.with_customer_ids(filter, ids)
  end

  defp people_by_id(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> %{}
      ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})
    end
  end

  defp with_customer(record, people) do
    person = Map.get(people, record.user_id)

    Map.merge(record, %{
      customer_name: person && person.nickname,
      customer_handle: person && person.handle,
      customer_email: person && person.email
    })
  end

  defp name_of(_people, nil), do: nil

  defp name_of(people, id) do
    case Map.get(people, id) do
      nil -> nil
      person -> person.nickname
    end
  end

  defp with_balance_due(%{record_type: type, id: id} = record, context)
       when type in ["invoice", "receipt"] do
    balance = context |> Finance.invoice_balance_due_map([id]) |> Map.get(id, 0)
    Map.put(record, :balance_due_cents, balance)
  end

  defp with_balance_due(record, _context), do: record
end
