defmodule Palee.Application.DebtorContactsTest do
  @moduledoc """
  ADR-450: a profile deleted while it owes a box money. The box keeps the
  name, email and SMS number until the debt is settled, sees them on
  «Οφειλές», and the reminder goes to the kept email.
  """

  use Palee.DataCase, async: false
  use Palee.EmailCase
  use Oban.Testing, repo: Palee.Repo

  alias Palee.Application.{AccountDeletion, DebtorContacts, GetFinanceOperationalQueues}
  alias Palee.{Finance, Identity, Organizations}
  alias Palee.Identity.AccountDeletionStore
  alias Palee.Infrastructure.Security.MemoryTokenStore
  alias Palee.TestFixtures
  alias Palee.Workers.PaymentReminderJob

  @password "S3cur3P@ss!42"
  @now ~U[2026-11-02 10:00:00.000000Z]

  setup do
    MemoryTokenStore.reset!()
    owner = TestFixtures.admin_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "Debt Box"})

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    %{context: context}
  end

  defp member(name) do
    unique = System.unique_integer([:positive])
    email = "debtor_#{unique}@placeholder.invalid"

    {:ok, account} =
      Identity.register(%{
        nickname: "#{name}#{unique}",
        password: @password,
        role: :member,
        email: email
      })

    :ok = Identity.mark_email_verified(account.login_id, email)
    Identity.find_by_id(account.id)
  end

  defp owing(context, account, cents) do
    {:ok, membership} =
      Finance.upsert_membership(context, account.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, invoice} =
      Finance.create_invoice(context, membership.id, %{
        amount_cents: cents,
        description: "Monthly",
        due_date: Date.add(Date.utc_today(), -3)
      })

    {:ok, invoice} = Finance.issue_invoice(context, invoice.id, %{})
    {membership, invoice}
  end

  defp delete_account(account) do
    {:ok, _} = AccountDeletion.request(account, %{scope: "login", password: @password}, @now)
    message = assert_email_enqueued(kind: :account_deletion_confirm, to: account.email)
    [_, token] = Regex.run(~r/#token=([A-Za-z0-9_-]{43})/, message.text)
    {:ok, %{scheduled_for: at}} = AccountDeletion.confirm(token, @now)

    # Like the hourly job in production: no session scope, runtime role.
    with_clean_session(fn -> with_runtime_role(fn -> AccountDeletion.execute_due(at) end) end)
  end

  test "the box keeps how to reach a deleted debtor, shows it on «Οφειλές» and emails the reminder",
       %{context: context} do
    debtor = member("eleni")
    {membership, invoice} = owing(context, debtor, 4_000)

    {:ok, _sms} =
      Palee.Channels.save_contact(context, {:user, debtor.id}, %{phone: "6912345678"}, "GR")

    assert delete_account(debtor) == 1

    kept = Identity.find_by_id(debtor.id)
    assert kept.nickname == "Deleted account"

    contact = context |> DebtorContacts.labels([debtor.id]) |> Map.fetch!(debtor.id)
    assert contact.display_name == debtor.nickname
    assert contact.email == debtor.email
    # The box's SMS number is forgotten with the account (ADR-348), but kept here.
    assert contact.phone_e164 == "+306912345678"

    {:ok, %{queues: %{open_charges: rows}}} = GetFinanceOperationalQueues.call(context, %{})
    row = Enum.find(rows, &(&1.user_id == debtor.id))
    assert row.user_label == debtor.nickname
    assert row.kept_contact.email == debtor.email

    # The reminder goes to the kept email; the anonymised profile has no app.
    assert :ok = perform_job(PaymentReminderJob, %{})
    reminder = assert_email_enqueued(kind: :debt_reminder, to: debtor.email)
    assert reminder.text =~ "40.00 €"
    assert reminder.text =~ "Debt Box"

    # Paid in full: the contact goes at the box's next daily run.
    {:ok, _payment} =
      Finance.record_payment(context, membership.id, %{
        finance_invoice_id: invoice.id,
        amount_cents: 4_000,
        payment_method: "cash",
        payment_status: "paid",
        paid_on: Date.utc_today()
      })

    assert DebtorContacts.release_settled(context) == 1
    assert DebtorContacts.labels(context, [debtor.id]) == %{}
  end

  test "nothing is kept for a profile that owes nothing", %{context: context} do
    settled = member("nikos")

    {:ok, _membership} =
      Finance.upsert_membership(context, settled.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    assert delete_account(settled) == 1
    assert DebtorContacts.labels(context, [settled.id]) == %{}
  end

  test "the boxes of a profile are listed only while its deletion is scheduled", %{
    context: context
  } do
    someone = member("maria")
    owing(context, someone, 1_000)

    assert AccountDeletionStore.deleting_profile_memberships(someone.id) == []
  end
end
