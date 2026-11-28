defmodule Palee.Finance.PackagePaymentStandingTest do
  # One standing for a member's package and its money, whichever way staff
  # record it: the desk queue, the ledger, «+ Πληρωμή» or an assignment.
  use Palee.DataCase

  alias Palee.{Finance, Organizations}
  alias Palee.Finance.PackageRequestStore
  alias Palee.TestFixtures

  setup do
    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Pay #{System.unique_integer([:positive])}"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", owner.id])

    package = fn name ->
      {:ok, package} =
        Finance.create_package(%{
          name: "#{name} #{System.unique_integer([:positive])}",
          package_type: "membership",
          billing_period: "monthly",
          base_price_cents: 5000,
          fields: %{"terms.auto_renew" => true}
        })

      package
    end

    user = TestFixtures.user_fixture(%{role: :member})

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    %{
      organization: organization,
      user: user,
      membership: membership,
      monthly: package.("Monthly"),
      other: package.("Other")
    }
  end

  defp profile(user), do: Finance.get_member_profile(user.id)

  defp ask(user, package) do
    {:ok, request, :created} =
      PackageRequestStore.request(%{
        user_id: user.id,
        membership_package_id: package.id,
        package_name_snapshot: package.name,
        price_cents_snapshot: package.base_price_cents,
        currency: "EUR",
        source: "member",
        requested_by_id: user.id,
        hold_until: Date.add(gym_today(), 14),
        today: gym_today()
      })

    request
  end

  defp receive(membership, params) do
    Finance.receive_payment(
      membership.id,
      Map.merge(%{"idempotency_key" => Ecto.UUID.generate(), "payment_method" => "cash"}, params)
    )
  end

  test "paying at the desk for a package the member already holds unpaid settles its charge",
       %{user: user, membership: membership, monthly: monthly} do
    {:ok, subscription} = Finance.assign_package(membership.id, monthly.id, %{})
    [charge] = profile(user).invoices
    assert profile(user).membership.status_shown == "unpaid"
    assert %{status: "unpaid", outstanding_cents: 5000} = profile(user).standing

    {:ok, received} =
      receive(membership, %{"purchase_package_id" => monthly.id, "amount_cents" => 5000})

    assert received.invoice.id == charge.id
    assert received.membership_package_subscription_id == subscription.id
    assert [%{id: id}] = profile(user).package_subscriptions
    assert id == subscription.id
    assert [%{balance_due_cents: 0}] = profile(user).invoices
    assert profile(user).membership.status_shown == "active"

    # Every screen reads this one standing: nothing owed, nothing pending.
    assert %{status: "active", outstanding_cents: 0, unpaid_since: nil} = profile(user).standing
  end

  test "money that settles a package's charge fulfils the «Το θέλω» waiting for it",
       %{user: user, membership: membership, monthly: monthly} do
    {:ok, subscription} = Finance.assign_package(membership.id, monthly.id, %{})
    request = ask(user, monthly)

    {:ok, _received} =
      receive(membership, %{
        "membership_package_subscription_id" => subscription.id,
        "amount_cents" => 5000
      })

    closed = PackageRequestStore.get(request.id)
    assert closed.status == "activated"
    assert closed.membership_package_subscription_id == subscription.id
  end

  test "assigning the package asked for fulfils the request", %{
    user: user,
    membership: membership,
    monthly: monthly
  } do
    request = ask(user, monthly)
    {:ok, subscription} = Finance.assign_package(membership.id, monthly.id, %{})

    closed = PackageRequestStore.get(request.id)
    assert closed.status == "activated"
    assert closed.membership_package_subscription_id == subscription.id
  end

  test "the hourly run fulfils a request the box answered in a way no write closed", %{
    organization: organization,
    user: user,
    membership: membership,
    monthly: monthly,
    other: other
  } do
    answered = ask(user, monthly)
    waiting = ask(user, other)
    {:ok, subscription} = Finance.assign_package(membership.id, monthly.id, %{})

    # A request left open by a path that did not close it (before this fix).
    Palee.Repo.update_all(
      from(r in Palee.Finance.PackageRequest, where: r.id == ^answered.id),
      set: [status: "pending", closed_at: nil]
    )

    assert Palee.Application.Finance.PackageRequests.lapse(%{organization_id: organization.id}) ==
             0

    assert %{status: "activated", membership_package_subscription_id: id} =
             PackageRequestStore.get(answered.id)

    assert id == subscription.id
    # Nothing of the other package was given: it still waits.
    assert PackageRequestStore.get(waiting.id).status == "pending"
  end
end
