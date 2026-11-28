defmodule Palee.Finance.PackageStartsTest do
  # ADR-795: a package starts with the member's first completed class or WOD
  # (the box's default) or on payment; a package that changed while it waited
  # starts only after the member's «Το κατάλαβα».
  use Palee.DataCase

  alias Palee.{Finance, Organizations}
  alias Palee.Application.Finance.PackageStarts
  alias Palee.Finance.{MembershipPackageSubscription, PackageStart, PackageTermsStore}
  alias Palee.TestFixtures

  @visits "group_classes.visits"
  @window "booking.window_days"

  setup do
    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Starts #{System.unique_integer([:positive])}"})

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

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        package_starts_with: "first_session"
      })

    {:ok, package} =
      Finance.create_package(%{
        name: "Unlimited #{System.unique_integer([:positive])}",
        package_type: "membership",
        billing_period: "monthly",
        base_price_cents: 5000,
        fields: %{
          "terms.auto_renew" => true,
          "group_classes.included" => true,
          @visits => %{"limit" => 12, "period" => "calendar_month"},
          @window => 7
        }
      })

    user = TestFixtures.user_fixture(%{role: :member})

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    %{
      owner: owner,
      context: %{organization_id: organization.id},
      package: package,
      user: user,
      membership: membership
    }
  end

  defp stored(subscription), do: Repo.get!(MembershipPackageSubscription, subscription.id)

  defp start_row(subscription),
    do: Repo.get_by!(PackageStart, subscription_id: subscription.id)

  defp charges(user),
    do:
      Enum.filter(
        Finance.get_member_profile(user.id).invoices,
        &(&1.invoice_type == "subscription")
      )

  defp visit(key) do
    %{
      channel: :in_person,
      capability: :book_classes,
      allowance: :class_visits,
      source_context: "scheduling",
      source_id: Ecto.UUID.generate(),
      quantity: 1,
      occurred_on: gym_today(),
      idempotency_key: key
    }
  end

  defp session(on \\ nil), do: %{kind: "class", id: Ecto.UUID.generate(), on: on || gym_today()}

  defp terms_change(package, attrs) do
    %{
      "name" => Map.get(attrs, :name, package.name),
      "base_price_cents" => Map.get(attrs, :price, 5000),
      "fields" => %{
        @visits => %{"limit" => Map.get(attrs, :visits, 12), "period" => "calendar_month"},
        @window => Map.get(attrs, :window, 7)
      }
    }
  end

  defp change!(package, owner, attrs) do
    # Nobody holds the package yet: a waiting subscription is no holder (ADR-770).
    assert {:ok, _saved} =
             PackageTermsStore.update(
               package.id,
               terms_change(package, attrs),
               %{apply_to: nil},
               owner.id
             )
  end

  test "a box that has not chosen starts packages with the first session" do
    previous = Application.get_env(:palee, :package_starts_default)
    Application.delete_env(:palee, :package_starts_default)
    on_exit(fn -> Application.put_env(:palee, :package_starts_default, previous) end)

    {:ok, _settings} = Finance.update_finance_settings(%{package_starts_with: nil})
    assert Finance.get_finance_settings().package_starts_with == "first_session"
  end

  test "a package given at the desk waits: no period, no charge, bookings allowed", %{
    user: user,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})

    waiting = stored(subscription)
    assert waiting.awaiting_first_session
    assert waiting.ends_on == nil
    assert waiting.charges_from == nil
    assert charges(user) == []
    assert start_row(subscription).status == "waiting"

    assert {:ok, _reservation} = Finance.reserve_entitlement(user.id, visit("wait:1"))
  end

  test "the first class starts it on that day and issues the first charge", %{
    context: context,
    user: user,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    day = gym_today()

    assert {:ok, {:started, start}} =
             Finance.begin_package_start(context, subscription.id, session(day))

    assert start.status == "started"
    assert start.started_on == day

    started = stored(subscription)
    refute started.awaiting_first_session
    assert started.starts_on == day
    assert started.activated_on == day
    assert started.charges_from == day
    assert [%{total_cents: 5000}] = charges(user)

    # A second session does nothing more.
    assert {:ok, :not_waiting} = Finance.begin_package_start(context, subscription.id, session())
  end

  test "a WOD the member finishes starts it (independent coaches)", %{
    context: context,
    user: user,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})

    assert :ok =
             PackageStarts.handle_event(:workout_result_recorded, %{
               organization_id: context.organization_id,
               user_id: user.id,
               workout_id: Ecto.UUID.generate(),
               at: DateTime.utc_now()
             })

    assert start_row(subscription).status == "started"
    assert start_row(subscription).session_kind == "workout"
    refute stored(subscription).awaiting_first_session
  end

  test "«Δεν ήρθε» does not start it", %{
    context: context,
    user: user,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})

    assert :ok =
             PackageStarts.handle_event(:attendance_recorded, %{
               organization_id: context.organization_id,
               user_id: user.id,
               scheduled_class_id: Ecto.UUID.generate(),
               status: "no_show"
             })

    assert stored(subscription).awaiting_first_session
  end

  test "with «on payment» the package starts at once", %{
    user: user,
    membership: membership,
    package: package
  } do
    {:ok, _settings} = Finance.update_finance_settings(%{package_starts_with: "payment"})
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})

    refute stored(subscription).awaiting_first_session
    assert stored(subscription).charges_from == gym_today()
    assert [%{total_cents: 5000}] = charges(user)
    assert Repo.get_by(PackageStart, subscription_id: subscription.id) == nil
  end

  test "an explicit start day (imports, seasons) never waits", %{
    membership: membership,
    package: package
  } do
    {:ok, subscription} =
      Finance.assign_package(membership.id, package.id, %{
        "starts_on" => Date.to_iso8601(gym_today())
      })

    refute stored(subscription).awaiting_first_session
  end

  test "a price rise while waiting is important: bookings stop until «Το κατάλαβα»; the first period keeps the paid price",
       %{context: context, owner: owner, user: user, membership: membership, package: package} do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    change!(package, owner, %{price: 6000})

    assert {:ok, {:review, start}} =
             Finance.begin_package_start(context, subscription.id, session())

    assert start.severity == "important"

    assert [%{"key" => "price", "from" => 5000, "to" => 6000, "severity" => "important"}] =
             start.changes

    assert stored(subscription).awaiting_first_session
    assert charges(user) == []

    assert {:error, :finance_package_review_required} =
             Finance.reserve_entitlement(user.id, visit("review:1"))

    assert {:ok, started} = PackageStarts.acknowledge(context, user.id, start.id)
    assert started.status == "started"
    assert started.acknowledged_by_id == user.id

    assert [%{total_cents: 5000}] = charges(user)
    assert stored(subscription).price_cents_snapshot == 6000
    assert {:ok, _reservation} = Finance.reserve_entitlement(user.id, visit("review:2"))
  end

  test "fewer benefits are serious and the started package takes them", %{
    context: context,
    owner: owner,
    user: user,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    change!(package, owner, %{visits: 8})

    assert {:ok, {:review, start}} =
             Finance.begin_package_start(context, subscription.id, session())

    assert start.severity == "serious"
    assert {:ok, _started} = PackageStarts.acknowledge(context, user.id, start.id)
    assert stored(subscription).params_snapshot["fields"][@visits]["limit"] == 8
  end

  test "a new name alone is a warning", %{
    context: context,
    owner: owner,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    change!(package, owner, %{name: package.name <> " Plus"})

    assert {:ok, {:review, start}} =
             Finance.begin_package_start(context, subscription.id, session())

    assert start.severity == "warning"
    assert [%{"key" => "name", "severity" => "warning"}] = start.changes
  end

  test "a package that changed again since the member looked asks again", %{
    context: context,
    owner: owner,
    user: user,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    change!(package, owner, %{price: 6000})

    assert {:ok, {:review, start}} =
             Finance.begin_package_start(context, subscription.id, session())

    change!(package, owner, %{price: 7000})

    assert {:error, :package_changed_again} =
             PackageStarts.acknowledge(context, user.id, start.id)

    assert [%{"to" => 7000}] = start_row(subscription).changes
    assert {:ok, _started} = PackageStarts.acknowledge(context, user.id, start.id)
  end

  test "only the member's own review can be acknowledged", %{
    context: context,
    owner: owner,
    membership: membership,
    package: package
  } do
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    change!(package, owner, %{price: 6000})

    assert {:ok, {:review, start}} =
             Finance.begin_package_start(context, subscription.id, session())

    stranger = TestFixtures.user_fixture(%{role: :member})
    assert {:error, :not_found} = PackageStarts.acknowledge(context, stranger.id, start.id)
  end

  test "packages sold with «first use» keep starting at the first reservation", %{
    user: user,
    membership: membership
  } do
    {:ok, _settings} = Finance.update_finance_settings(%{package_starts_with: "payment"})

    {:ok, pack} =
      Finance.create_package(%{
        name: "Pack #{System.unique_integer([:positive])}",
        package_type: "class_pack",
        fields: %{"terms.validity" => %{"amount" => 1, "unit" => "month"}}
      })

    {:ok, subscription} = Finance.assign_package(membership.id, pack.id, %{charge_now: false})
    legacy = stored(subscription)
    fields = Map.put(legacy.params_snapshot["fields"], "terms.validity_starts", "first_use")

    legacy
    |> Ecto.Changeset.change(
      params_snapshot: Map.put(legacy.params_snapshot, "fields", fields),
      ends_on: nil
    )
    |> Repo.update!()

    assert {:ok, _reservation} = Finance.reserve_entitlement(user.id, visit("legacy:1"))
    assert stored(subscription).activated_on == gym_today()
    assert stored(subscription).ends_on
  end

  test "«Να μην εμφανιστεί ξανά σήμερα» holds for that person, question and day", %{
    context: context,
    owner: owner,
    user: user
  } do
    day = gym_today()
    assert Finance.confirmation_skips(context, owner.id, day) == []
    assert :ok = Finance.skip_confirmation(context, owner.id, "record_payment", day)
    assert :ok = Finance.skip_confirmation(context, owner.id, "record_payment", day)
    assert Finance.confirmation_skips(context, owner.id, day) == ["record_payment"]
    assert Finance.confirmation_skips(context, owner.id, Date.add(day, 1)) == []
    assert Finance.confirmation_skips(context, user.id, day) == []
    assert {:error, %Ecto.Changeset{}} = Finance.skip_confirmation(context, owner.id, "nope", day)
  end
end
