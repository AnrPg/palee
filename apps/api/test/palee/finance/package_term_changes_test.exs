defmodule Palee.Finance.PackageTermChangesTest do
  # ADR-770: a package change reaches the members who hold the package only
  # when staff choose so: better terms now, a price rise or fewer benefits
  # from each holder's next period; left-out holders keep theirs.
  use Palee.DataCase

  alias Palee.{Finance, Organizations}
  alias Palee.Finance.{MembershipPackageSubscription, PackageTermsStore, SubscriptionTermUpdate}
  alias Palee.TestFixtures

  @visits "group_classes.visits"
  @window "booking.window_days"

  setup do
    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Terms #{System.unique_integer([:positive])}"})

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

    {:ok, package} =
      Finance.create_package(%{
        name: "Unlimited #{System.unique_integer([:positive])}",
        package_type: "membership",
        billing_period: "monthly",
        base_price_cents: 6000,
        fields: %{
          "terms.auto_renew" => true,
          "group_classes.included" => true,
          @visits => %{"limit" => 12, "period" => "calendar_month"},
          @window => 7
        }
      })

    holder = fn ->
      user = TestFixtures.user_fixture(%{role: :member})

      {:ok, membership} =
        Finance.upsert_membership(user.id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "direct"
        })

      {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
      %{user: user, membership: membership, subscription: subscription}
    end

    %{owner: owner, package: package, holder: holder}
  end

  defp change(package, price, visits, window) do
    %{
      "base_price_cents" => price,
      "fields" => %{
        @visits => %{"limit" => visits, "period" => "calendar_month"},
        @window => window
      }
    }
    |> Map.put("name", package.name)
  end

  defp stored(subscription), do: Repo.get!(MembershipPackageSubscription, subscription.id)

  defp fields(subscription), do: stored(subscription).params_snapshot["fields"]

  defp updates(subscription),
    do:
      Repo.all(
        from(u in SubscriptionTermUpdate,
          where: u.subscription_id == ^subscription.id,
          order_by: u.inserted_at
        )
      )

  test "saving a change that reaches holders needs a choice and saves nothing without one",
       %{package: package, holder: holder, owner: owner} do
    %{subscription: subscription} = holder.()

    assert {:error, :package_terms_choice_required} =
             PackageTermsStore.update(
               package.id,
               change(package, 6500, 8, 14),
               %{apply_to: nil},
               owner.id
             )

    assert Finance.get_package(package.id).base_price_cents == 6000
    assert fields(subscription)[@window] == 7
  end

  test "the preview tells what would happen and saves nothing",
       %{package: package, holder: holder} do
    %{subscription: subscription, user: user} = holder.()

    assert {:ok, preview} = PackageTermsStore.preview(package.id, change(package, 6500, 8, 14))
    assert preview.holders_count == 1
    assert preview.needs_choice

    timings = Map.new(preview.changes, &{&1.key, &1.timing})
    assert timings == %{"price" => "next_period", @visits => "next_period", @window => "now"}

    assert [%{subscription_id: id, user_id: user_id, next_period_on: %Date{}}] = preview.holders
    assert id == subscription.id and user_id == user.id
    assert Finance.get_package(package.id).base_price_cents == 6000
  end

  test "«Και στα ενεργά μέλη»: better terms now, the rest from the next period",
       %{package: package, holder: holder, owner: owner} do
    %{subscription: subscription, user: user} = holder.()

    assert {:ok, %{notices: [notice]}} =
             PackageTermsStore.update(
               package.id,
               change(package, 6500, 8, 14),
               %{apply_to: "active", excluded_subscription_ids: []},
               owner.id
             )

    assert notice.user_id == user.id
    assert notice.now_count == 1
    next_on = Date.shift(subscription.starts_on, month: 1)
    assert notice.next_on == next_on

    # Now: the wider booking window. The price and visits wait.
    assert fields(subscription)[@window] == 14
    assert fields(subscription)[@visits] == %{"limit" => 12, "period" => "calendar_month"}
    assert stored(subscription).price_cents_snapshot == 6000

    assert [
             %{timing: "now", status: "applied"},
             %{
               timing: "next_period",
               status: "pending",
               effective_on: ^next_on,
               price_cents: 6500
             }
           ] =
             updates(subscription)

    # Before the day nothing moves; on it the pending terms apply once.
    refute PackageTermsStore.apply_due(subscription.id, Date.add(next_on, -1))
    assert PackageTermsStore.apply_due(subscription.id, next_on)
    refute PackageTermsStore.apply_due(subscription.id, next_on)

    assert stored(subscription).price_cents_snapshot == 6500
    assert fields(subscription)[@visits] == %{"limit" => 8, "period" => "calendar_month"}
  end

  test "«Μόνο στις νέες αγορές» and left-out holders keep their terms",
       %{package: package, holder: holder, owner: owner} do
    %{subscription: kept} = holder.()
    %{subscription: changed} = holder.()

    assert {:ok, %{notices: [_one]}} =
             PackageTermsStore.update(
               package.id,
               change(package, 6000, 12, 14),
               %{apply_to: "active", excluded_subscription_ids: [kept.id]},
               owner.id
             )

    assert fields(kept)[@window] == 7
    assert fields(changed)[@window] == 14

    assert {:ok, %{notices: []}} =
             PackageTermsStore.update(
               package.id,
               change(package, 6000, 12, 21),
               %{apply_to: "new_only", excluded_subscription_ids: []},
               owner.id
             )

    assert fields(changed)[@window] == 14
    assert Finance.get_package(package.id).params["fields"][@window] == 21
  end

  test "a later change merges into the pending one (ζ)",
       %{package: package, holder: holder, owner: owner} do
    %{subscription: subscription} = holder.()
    choice = %{apply_to: "active", excluded_subscription_ids: []}

    {:ok, _} =
      PackageTermsStore.update(package.id, change(package, 6500, 12, 7), choice, owner.id)

    {:ok, _} = PackageTermsStore.update(package.id, change(package, 6500, 8, 7), choice, owner.id)

    assert [%{status: "superseded"}, %{status: "pending", price_cents: 6500, fields: fields}] =
             updates(subscription)

    assert fields == %{@visits => %{"limit" => 8, "period" => "calendar_month"}}
  end

  test "a member who stopped renewing keeps the price",
       %{package: package, holder: holder, owner: owner} do
    %{subscription: subscription} = holder.()

    subscription
    |> stored()
    |> Ecto.Changeset.change(auto_renew: false)
    |> Repo.update!()

    {:ok, %{notices: []}} =
      PackageTermsStore.update(
        package.id,
        change(package, 6500, 12, 7),
        %{apply_to: "active", excluded_subscription_ids: []},
        owner.id
      )

    assert updates(subscription) == []
    assert stored(subscription).price_cents_snapshot == 6000
  end

  test "a change only to the name asks nothing", %{package: package, holder: holder, owner: owner} do
    holder.()

    assert {:ok, %{term_change_id: nil}} =
             PackageTermsStore.update(
               package.id,
               %{"name" => "Renamed #{System.unique_integer([:positive])}"},
               %{apply_to: nil},
               owner.id
             )
  end
end
