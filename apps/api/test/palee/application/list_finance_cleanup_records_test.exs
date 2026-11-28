defmodule Palee.Application.ListFinanceCleanupRecordsTest do
  use Palee.DataCase

  alias Palee.{Finance, Organizations}
  alias Palee.Application.ListFinanceCleanupRecords
  alias Palee.TestFixtures

  setup do
    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Cleanup #{System.unique_integer([:positive])}"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", owner.id])

    {:ok, monthly} =
      Finance.create_package(%{
        name: "Monthly cleanup",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    {:ok, drop_in} =
      Finance.create_package(%{
        name: "Drop-in cleanup",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 1_500
      })

    maria =
      TestFixtures.user_fixture(%{nickname: "maria_cleanup", email: "maria.cleanup@example.com"})

    nikos = TestFixtures.user_fixture(%{nickname: "nikos_cleanup"})

    maria_receipt = receipt!(maria, monthly, owner, ~D[2026-11-10], 6_000)
    nikos_receipt = receipt!(nikos, drop_in, owner, ~D[2026-10-05], 1_500)

    # Old records may belong to a package the box no longer sells.
    # (Retiring a sold package needs a reconciliation step; set the flag directly.)
    {1, _rows} =
      Palee.Finance.MembershipPackage
      |> where([package], package.id == ^drop_in.id)
      |> Repo.update_all(set: [active: false])

    %{
      context: context,
      owner: owner,
      maria: maria,
      monthly: monthly,
      drop_in: drop_in,
      maria_receipt: maria_receipt,
      nikos_receipt: nikos_receipt
    }
  end

  defp receipt!(user, package, owner, paid_on, amount) do
    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{starts_on: paid_on})

    {:ok, receipt} =
      Finance.create_receipt(membership.id, %{
        amount_cents: amount,
        payment_method: "cash",
        paid_on: paid_on,
        description: package.name,
        membership_package_subscription_id: subscription.id,
        created_by_id: owner.id,
        idempotency_key: "cleanup-#{System.unique_integer([:positive])}"
      })

    receipt
  end

  defp ids(context, params) do
    {:ok, %{records: records}} = ListFinanceCleanupRecords.call(context, params)
    Enum.map(records, & &1.id) |> Enum.sort()
  end

  test "rows carry the customer and the package", %{context: context, maria: maria} = ctx do
    {:ok, %{records: records}} = ListFinanceCleanupRecords.call(context, %{})

    receipt = Enum.find(records, &(&1.id == ctx.maria_receipt.invoice.id))
    payment = Enum.find(records, &(&1.id == ctx.maria_receipt.payment.id))

    assert receipt.record_type == "receipt"
    assert receipt.customer_name == maria.nickname
    assert receipt.customer_email == "maria.cleanup@example.com"
    assert receipt.package_name == "Monthly cleanup"
    assert receipt.occurred_on == ~D[2026-11-10]
    assert payment.record_type == "payment"
    assert payment.payment_method == "cash"
    assert payment.customer_name == maria.nickname
    assert payment.package_name == "Monthly cleanup"
    assert payment.code == ctx.maria_receipt.invoice.invoice_number
  end

  test "one search field finds name, email and document number", %{context: context} = ctx do
    maria_ids = ids(context, %{"user_id" => ctx.maria.id})
    assert ctx.maria_receipt.invoice.id in maria_ids
    assert ctx.maria_receipt.payment.id in maria_ids

    assert ids(context, %{"q" => "maria_clean"}) == maria_ids
    assert ids(context, %{"q" => "MARIA.CLEANUP@example"}) == maria_ids

    assert ids(context, %{"q" => ctx.nikos_receipt.invoice.invoice_number}) ==
             Enum.sort([ctx.nikos_receipt.invoice.id, ctx.nikos_receipt.payment.id])

    assert ids(context, %{"q" => "nobody-matches-this"}) == []
  end

  test "filters by customer, dates, package (inactive too) and kind", %{context: context} = ctx do
    november = ids(context, %{"from" => "2026-11-01", "to" => "2026-11-30"})
    assert ctx.maria_receipt.invoice.id in november
    assert ctx.maria_receipt.payment.id in november
    refute ctx.nikos_receipt.invoice.id in november
    refute ctx.nikos_receipt.payment.id in november

    drop_in = ids(context, %{"package_id" => ctx.drop_in.id})
    assert ctx.nikos_receipt.invoice.id in drop_in
    assert ctx.nikos_receipt.payment.id in drop_in
    refute ctx.maria_receipt.invoice.id in drop_in

    assert ids(context, %{"kind" => "payment"}) ==
             Enum.sort([ctx.maria_receipt.payment.id, ctx.nikos_receipt.payment.id])

    receipts = ids(context, %{"kind" => "receipt"})
    assert receipts == Enum.sort([ctx.maria_receipt.invoice.id, ctx.nikos_receipt.invoice.id])
    assert Enum.all?(ids(context, %{"kind" => "invoice"}), &(&1 not in receipts))

    {:ok, %{packages: packages}} = ListFinanceCleanupRecords.packages(context)
    assert %{name: "Drop-in cleanup", active: false} = List.last(packages)
  end

  test "pages never repeat or skip a record", %{context: context} do
    all = ids(context, %{})
    assert length(all) > 3

    {:ok, first} = ListFinanceCleanupRecords.call(context, %{"limit" => "3"})
    assert length(first.records) == 3
    assert is_binary(first.next_cursor)

    {:ok, second} =
      ListFinanceCleanupRecords.call(context, %{"limit" => "100", "cursor" => first.next_cursor})

    assert second.next_cursor == nil

    paged = Enum.map(first.records ++ second.records, & &1.id)
    assert length(paged) == length(Enum.uniq(paged))
    assert Enum.sort(paged) == all
  end

  test "details show lines, the linked payment and who recorded it", %{context: context} = ctx do
    {:ok, %{record: receipt}} =
      ListFinanceCleanupRecords.get(context, "receipt", ctx.maria_receipt.invoice.id)

    assert receipt.created_by_name == ctx.owner.nickname
    assert receipt.balance_due_cents == 0
    assert [%{total_cents: 6_000}] = receipt.lines
    assert [%{id: payment_id, record_type: "payment"}] = receipt.linked
    assert payment_id == ctx.maria_receipt.payment.id

    {:ok, %{record: payment}} = ListFinanceCleanupRecords.get(context, "payment", payment_id)
    assert [%{record_type: "receipt", code: code}] = payment.linked
    assert code == ctx.maria_receipt.invoice.invoice_number

    assert {:error, :not_found} =
             ListFinanceCleanupRecords.get(context, "payment", Ecto.UUID.generate())

    assert {:error, :not_found} = ListFinanceCleanupRecords.get(context, "transfer", payment_id)
  end

  test "a purged record leaves the list", %{context: context, owner: owner} = ctx do
    assert {:ok, _purge} =
             Finance.soft_delete_finance_record(
               "payment",
               ctx.nikos_receipt.payment.id,
               owner.id,
               %{
                 reason: "Wrong"
               }
             )

    refute ctx.nikos_receipt.payment.id in ids(context, %{})
  end
end
