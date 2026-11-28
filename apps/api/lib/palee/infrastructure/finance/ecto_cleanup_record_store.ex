defmodule Palee.Infrastructure.Finance.EctoCleanupRecordStore do
  @moduledoc """
  ADR-797: the reads behind «Εκκαθάριση συναλλαγών». Lists the active
  invoices, receipts and payments of the current business with the filters
  of `Palee.Finance.Domain.CleanupRecordFilter`, and loads one record with
  everything its side panel shows (lines, linked records, package).

  Every query is tenant scoped here as well as by row-level security. People
  (names, emails) are not read here: they belong to Identity, so the records
  carry `user_id` and the application adds the names.
  """

  import Ecto.Query

  alias Palee.Finance.Domain.CleanupRecordFilter

  alias Palee.Finance.{
    FinanceInvoice,
    FinanceInvoiceLine,
    FinancePaymentReversal,
    Membership,
    MembershipPackage,
    MembershipPackageSubscription,
    MembershipPayment
  }

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @doc "One page of active records, newest first: `%{records, next_cursor}`."
  def list(%CleanupRecordFilter{} = filter) do
    fetch = filter.limit + 1

    documents =
      if CleanupRecordFilter.wants?(filter, :document),
        do:
          filter |> document_query() |> limit(^fetch) |> Repo.all() |> Enum.map(&document_row/1),
        else: []

    payments =
      if CleanupRecordFilter.wants?(filter, :payment),
        do: filter |> payment_query() |> limit(^fetch) |> Repo.all() |> Enum.map(&payment_row/1),
        else: []

    CleanupRecordFilter.page(filter, documents ++ payments)
  end

  @doc "One active record with its details, or nil."
  def get(type, id) when type in ["invoice", "receipt"] do
    with {:ok, id} <- Ecto.UUID.cast(id),
         row when not is_nil(row) <-
           CleanupRecordFilter.new(%{})
           |> document_query()
           |> where([invoice: invoice], invoice.id == ^id)
           |> Repo.one() do
      document_row(row) |> Map.merge(document_details(elem(row, 0)))
    else
      _missing -> nil
    end
  end

  def get("payment", id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         row when not is_nil(row) <-
           CleanupRecordFilter.new(%{})
           |> payment_query()
           |> where([payment: payment], payment.id == ^id)
           |> Repo.one() do
      payment_row(row) |> Map.merge(payment_details(elem(row, 0), elem(row, 1)))
    else
      _missing -> nil
    end
  end

  def get(_type, _id), do: nil

  @doc "Everyone who ever had a membership in this business (the people a search can match)."
  def customer_user_ids do
    from(membership in tenant_scope(Membership),
      where: not is_nil(membership.user_id),
      distinct: true,
      select: membership.user_id
    )
    |> Repo.all()
  end

  @doc "The list shape of a document, without package (the purge result)."
  def document_record(%FinanceInvoice{} = invoice), do: document_row({invoice, nil, nil})

  @doc "The list shape of a payment, without package (the purge result)."
  def payment_record(%MembershipPayment{} = payment) do
    invoice =
      if payment.finance_invoice_id,
        do: FinanceInvoice |> tenant_scope() |> Repo.get(payment.finance_invoice_id)

    payment_row({payment, invoice, nil, nil, nil})
  end

  # -- queries -------------------------------------------------------------

  defp document_query(%CleanupRecordFilter{} = filter) do
    from(invoice in tenant_scope(FinanceInvoice),
      as: :invoice,
      left_join: subscription in MembershipPackageSubscription,
      on: subscription.id == invoice.membership_package_subscription_id,
      left_join: package in MembershipPackage,
      on: package.id == subscription.membership_package_id,
      where: is_nil(invoice.deleted_at),
      select: {invoice, package.id, package.name},
      order_by: [desc: invoice.inserted_at, desc: invoice.id]
    )
    |> document_kind(filter.kind)
    |> document_text(filter.q, filter.customer_ids)
    |> where_if(filter.user_id, fn query, user_id ->
      where(query, [invoice: invoice], invoice.user_id == ^user_id)
    end)
    |> where_if(filter.package_id, &document_package/2)
    |> where_if(filter.from, fn query, from ->
      where(
        query,
        [invoice: invoice],
        fragment("COALESCE(?, (?)::date)", invoice.issue_date, invoice.inserted_at) >= ^from
      )
    end)
    |> where_if(filter.to, fn query, to ->
      where(
        query,
        [invoice: invoice],
        fragment("COALESCE(?, (?)::date)", invoice.issue_date, invoice.inserted_at) <= ^to
      )
    end)
    |> where_if(filter.cursor, fn query, {at, id} ->
      where(
        query,
        [invoice: invoice],
        invoice.inserted_at < ^at or
          (invoice.inserted_at == ^at and invoice.id < type(^id, :binary_id))
      )
    end)
  end

  defp payment_query(%CleanupRecordFilter{} = filter) do
    from(payment in tenant_scope(MembershipPayment),
      as: :payment,
      left_join: invoice in FinanceInvoice,
      on: invoice.id == payment.finance_invoice_id,
      as: :linked_invoice,
      left_join: membership in Membership,
      on: membership.id == payment.membership_id,
      as: :membership,
      left_join: subscription in MembershipPackageSubscription,
      on:
        subscription.id ==
          coalesce(
            payment.membership_package_subscription_id,
            invoice.membership_package_subscription_id
          ),
      as: :subscription,
      left_join: package in MembershipPackage,
      on: package.id == subscription.membership_package_id,
      where: is_nil(payment.deleted_at),
      select: {payment, invoice, membership.user_id, package.id, package.name},
      order_by: [desc: payment.inserted_at, desc: payment.id]
    )
    |> payment_text(filter.q, filter.customer_ids)
    |> where_if(filter.user_id, fn query, user_id ->
      where(query, [membership: membership], membership.user_id == ^user_id)
    end)
    |> where_if(filter.package_id, fn query, package_id ->
      where(
        query,
        [subscription: subscription],
        subscription.membership_package_id == ^package_id
      )
    end)
    |> where_if(filter.from, fn query, from ->
      where(
        query,
        [payment: payment],
        fragment("COALESCE(?, (?)::date)", payment.paid_on, payment.inserted_at) >= ^from
      )
    end)
    |> where_if(filter.to, fn query, to ->
      where(
        query,
        [payment: payment],
        fragment("COALESCE(?, (?)::date)", payment.paid_on, payment.inserted_at) <= ^to
      )
    end)
    |> where_if(filter.cursor, fn query, {at, id} ->
      where(
        query,
        [payment: payment],
        payment.inserted_at < ^at or
          (payment.inserted_at == ^at and payment.id < type(^id, :binary_id))
      )
    end)
  end

  defp document_kind(query, "receipt"),
    do:
      where(
        query,
        [invoice: invoice],
        fragment("?->>'document_kind' = 'receipt'", invoice.params)
      )

  defp document_kind(query, "invoice"),
    do:
      where(
        query,
        [invoice: invoice],
        fragment("COALESCE(?->>'document_kind', '') <> 'receipt'", invoice.params)
      )

  defp document_kind(query, _all), do: query

  # A document of the package directly, or through one of its lines.
  defp document_package(query, package_id) do
    subscriptions =
      from(subscription in MembershipPackageSubscription,
        where: subscription.membership_package_id == ^package_id,
        select: subscription.id
      )

    where(
      query,
      [invoice: invoice],
      invoice.membership_package_subscription_id in subquery(subscriptions) or
        exists(
          from(line in FinanceInvoiceLine,
            where:
              line.finance_invoice_id == parent_as(:invoice).id and
                line.membership_package_subscription_id in subquery(subscriptions),
            select: 1
          )
        )
    )
  end

  defp document_text(query, nil, _customer_ids), do: query

  defp document_text(query, text, customer_ids) do
    pattern = like_pattern(text)

    where(
      query,
      [invoice: invoice],
      ilike(invoice.invoice_number, ^pattern) or
        fragment("?::text ILIKE ?", invoice.id, ^pattern) or
        invoice.user_id in ^customer_ids
    )
  end

  defp payment_text(query, nil, _customer_ids), do: query

  defp payment_text(query, text, customer_ids) do
    pattern = like_pattern(text)

    where(
      query,
      [payment: payment, linked_invoice: invoice, membership: membership],
      fragment("?::text ILIKE ?", payment.id, ^pattern) or
        ilike(invoice.invoice_number, ^pattern) or
        membership.user_id in ^customer_ids
    )
  end

  defp where_if(query, nil, _fun), do: query
  defp where_if(query, value, fun), do: fun.(query, value)

  defp like_pattern(text) do
    escaped = String.replace(text, ~r/([\\%_])/, "\\\\\\1")
    "%#{escaped}%"
  end

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _none ->
        from(row in queryable, where: false)
    end
  end

  # -- shapes --------------------------------------------------------------

  defp document_row({%FinanceInvoice{} = invoice, package_id, package_name}) do
    %{
      id: invoice.id,
      organization_id: invoice.organization_id,
      record_type: document_type(invoice),
      code: invoice.invoice_number,
      membership_id: invoice.membership_id,
      user_id: invoice.user_id,
      finance_invoice_id: nil,
      amount_cents: invoice.total_cents,
      currency: invoice.currency,
      status: invoice.status,
      issued_on: invoice.issue_date,
      due_on: invoice.due_date,
      paid_on: nil,
      occurred_on: invoice.issue_date || DateTime.to_date(invoice.inserted_at),
      payment_method: nil,
      package_id: package_id,
      package_name: package_name,
      inserted_at: invoice.inserted_at,
      deleted_at: invoice.deleted_at
    }
  end

  defp payment_row({%MembershipPayment{} = payment, invoice, user_id, package_id, package_name}) do
    %{
      id: payment.id,
      organization_id: payment.organization_id,
      record_type: "payment",
      code: invoice && invoice.invoice_number,
      membership_id: payment.membership_id,
      user_id: user_id || (invoice && invoice.user_id),
      finance_invoice_id: payment.finance_invoice_id,
      amount_cents: payment.amount_cents,
      currency: payment.currency,
      status: payment.payment_status,
      issued_on: nil,
      due_on: nil,
      paid_on: payment.paid_on,
      occurred_on: payment.paid_on || DateTime.to_date(payment.inserted_at),
      payment_method: payment.payment_method,
      package_id: package_id,
      package_name: package_name,
      inserted_at: payment.inserted_at,
      deleted_at: payment.deleted_at
    }
  end

  defp document_details(%FinanceInvoice{} = invoice) do
    payments =
      from(payment in tenant_scope(MembershipPayment),
        where: payment.finance_invoice_id == ^invoice.id and is_nil(payment.deleted_at),
        order_by: [asc: payment.paid_on, asc: payment.inserted_at]
      )
      |> Repo.all()

    %{
      invoice_type: invoice.invoice_type,
      service_period_start: invoice.service_period_start,
      service_period_end: invoice.service_period_end,
      subtotal_cents: invoice.subtotal_cents,
      discount_cents: invoice.discount_cents,
      notes: blank_to_nil(invoice.notes),
      fiscal_receipt_ref: invoice.fiscal_receipt_ref,
      revenue_stream: invoice.revenue_stream,
      created_by_id:
        created_by(invoice.params) || Enum.find_value(payments, &created_by(&1.params)),
      lines:
        from(line in FinanceInvoiceLine,
          where: line.finance_invoice_id == ^invoice.id,
          order_by: [asc: line.inserted_at]
        )
        |> Repo.all()
        |> Enum.map(fn line ->
          %{
            id: line.id,
            description: line.description,
            quantity: line.quantity,
            unit_amount_cents: line.unit_amount_cents,
            discount_cents: line.discount_cents,
            total_cents: line.total_cents
          }
        end),
      linked: Enum.map(payments, &linked_payment/1)
    }
  end

  defp payment_details(%MembershipPayment{} = payment, invoice) do
    reversed_cents =
      from(reversal in tenant_scope(FinancePaymentReversal),
        where: reversal.membership_payment_id == ^payment.id and is_nil(reversal.deleted_at),
        select: coalesce(sum(reversal.amount_cents), 0)
      )
      |> Repo.one()

    %{
      notes: blank_to_nil(payment.notes),
      revenue_stream: payment.revenue_stream,
      reversed_cents: reversed_cents || 0,
      created_by_id: created_by(payment.params),
      lines: [],
      linked:
        if(invoice && is_nil(invoice.deleted_at),
          do: [
            %{
              id: invoice.id,
              record_type: document_type(invoice),
              code: invoice.invoice_number,
              amount_cents: invoice.total_cents,
              currency: invoice.currency,
              status: invoice.status,
              occurred_on: invoice.issue_date || DateTime.to_date(invoice.inserted_at)
            }
          ],
          else: []
        )
    }
  end

  defp linked_payment(%MembershipPayment{} = payment) do
    %{
      id: payment.id,
      record_type: "payment",
      code: nil,
      amount_cents: payment.amount_cents,
      currency: payment.currency,
      status: payment.payment_status,
      payment_method: payment.payment_method,
      occurred_on: payment.paid_on || DateTime.to_date(payment.inserted_at)
    }
  end

  defp document_type(%FinanceInvoice{params: params}) do
    if (params || %{})["document_kind"] == "receipt", do: "receipt", else: "invoice"
  end

  defp created_by(params) do
    case (params || %{})["created_by_id"] do
      id when is_binary(id) and id != "" -> id
      _none -> nil
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp blank_to_nil(_value), do: nil
end
