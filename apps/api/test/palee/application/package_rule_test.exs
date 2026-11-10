defmodule Palee.Application.PackageRuleTest do
  @moduledoc """
  ADR-633: «Χωρίς πακέτο, χωρίς κράτηση». In a box that sells packages a
  client books only with a package or a grace with an end; one class while
  their first «Το θέλω» waits, once per person and box. The rule starts by
  itself the first day the box sells a package, and the clients already
  training get 14 days from the system. Staff activate (paid or payment
  pending) or decline with a reason.
  """
  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  alias Palee.Application.{PackageRule, PlaceMemberInClass, SubmitBooking}
  alias Palee.Application.Finance.PackageRequests
  alias Palee.{Finance, Organizations, Repo}
  alias Palee.TestFixtures

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    owner = TestFixtures.admin_fixture(%{nickname: "rule_owner"})

    {:ok, organization} =
      Organizations.create_organization(%{name: "Rule Gym #{System.unique_integer([:positive])}"})

    owner_context = join_gym(organization, owner, :owner)
    veteran = TestFixtures.user_fixture(%{nickname: "rule_veteran"})
    veteran_context = join_gym(organization, veteran, :member)

    %{
      organization: organization,
      owner: owner,
      owner_context: owner_context,
      veteran: veteran,
      veteran_context: veteran_context
    }
  end

  defp join_gym(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end

  defp slot(ctx, attrs \\ %{}) do
    class_type = TestFixtures.class_type_fixture(%{tenant_context: ctx.owner_context})
    workout = TestFixtures.workout_fixture(ctx.owner, %{tenant_context: ctx.owner_context})

    TestFixtures.slot_fixture(
      workout,
      Map.merge(%{tenant_context: ctx.owner_context, class_type_id: class_type.id}, attrs)
    )
  end

  defp sell_package(ctx) do
    {:ok, package} =
      Finance.create_package(ctx.owner_context, %{
        name: "Μηνιαίο",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    package
  end

  defp newcomer(ctx, nickname) do
    user = TestFixtures.user_fixture(%{nickname: nickname})
    {user, join_gym(ctx.organization, user, :member)}
  end

  defp book(context, user, slot), do: SubmitBooking.call(context, user, slot.id)

  defp start_rule(ctx) do
    package = sell_package(ctx)
    assert PackageRule.daily(%{organization_id: ctx.organization.id}) == :started
    package
  end

  test "a box that sells no package keeps booking open", ctx do
    assert PackageRule.daily(%{organization_id: ctx.organization.id}) == :unchanged
    refute PackageRule.on?(ctx.owner_context)
    assert {:ok, _booking} = book(ctx.veteran_context, ctx.veteran, slot(ctx))
  end

  test "the first day the box sells a package, those already training get 14 days from the system",
       ctx do
    start_rule(ctx)
    assert PackageRule.on?(ctx.owner_context)

    profile = Finance.get_member_profile(ctx.owner_context, ctx.veteran.id)
    assert profile.membership.entitlement_source == "staff_free_access"

    assert profile.membership.entitlement_grace_until ==
             Date.add(Organizations.local_today(ctx.organization.id), 13)

    [grant] =
      Finance.with_tenant_context(ctx.owner_context, fn ->
        Palee.Finance.MemberBenefitStore.list_system_grants(PackageRule.rollout_reason())
      end)

    assert grant.actor_id == nil
    assert grant.actor_roles == ["system"]
    assert grant.kind == "free_access"

    assert %{since: %DateTime{}, people: [person]} = PackageRule.rollout(ctx.owner_context)
    assert person.user_id == ctx.veteran.id
    assert person.has_package == false

    assert {:ok, _booking} = book(ctx.veteran_context, ctx.veteran, slot(ctx))

    # The next day changes nothing and gives nothing twice.
    assert PackageRule.daily(%{organization_id: ctx.organization.id}) == :unchanged
  end

  test "a «Δωρεάν» status with no end gets the 14 days, then the package decides", ctx do
    {user, context} = newcomer(ctx, "rule_endless")

    {:ok, membership} =
      Finance.upsert_membership(ctx.owner_context, user.id, %{
        "status" => "active",
        "user_type_snapshot" => "member",
        "signup_source" => "admin_created"
      })

    # Set by hand before ADR-633, when «Δωρεάν» had no end.
    Finance.with_tenant_context(ctx.owner_context, fn ->
      %{
        membership_id: membership.id,
        subject_type: "membership",
        subject_id: membership.id,
        field: "status",
        value: "comped",
        computed_value: "no_package"
      }
      |> Palee.Finance.FinanceValueOverride.changeset()
      |> Repo.insert!()

      Repo.update_all(
        from(m in Palee.Finance.Membership, where: m.id == ^membership.id),
        set: [status: "comped"]
      )
    end)

    :ok = Finance.refresh_member_entitlement(ctx.owner_context, membership.id)

    assert Finance.get_member_profile(ctx.owner_context, user.id).membership.entitlement_source ==
             "comped"

    start_rule(ctx)

    membership = Finance.get_member_profile(ctx.owner_context, user.id).membership
    assert membership.entitlement_source == "staff_free_access"
    assert [%{end_reason: ended}] = Finance.list_value_overrides(ctx.owner_context, user.id)
    assert ended in ["reset", "lapsed"]
    assert {:ok, _booking} = book(context, user, slot(ctx))
    assert Enum.any?(PackageRule.rollout(ctx.owner_context).people, &(&1.user_id == user.id))
  end

  test "someone new books nothing without a package, then one class while «Το θέλω» waits",
       ctx do
    package = start_rule(ctx)
    {user, context} = newcomer(ctx, "rule_newcomer")

    assert %{rule: true, package_required: true, first_class_available: false} =
             PackageRule.standing(context, user.id)

    assert {:error, :finance_package_required} = book(context, user, slot(ctx))

    {:ok, %{request: request}} = PackageRequests.request(context, package.id)

    assert %{first_class_available: true, package_required: false, pending_request: true} =
             PackageRule.standing(context, user.id)

    first = slot(ctx)
    assert {:ok, booking} = book(context, user, first)
    assert {:error, :finance_package_required} = book(context, user, slot(ctx))

    # Once per person and box, whatever happens to that booking.
    assert {:ok, _withdrawn} =
             Palee.Application.WithdrawBooking.call(context, user.id, booking.id)

    assert {:error, :finance_package_required} = book(context, user, slot(ctx))

    stored =
      Finance.with_tenant_context(context, fn ->
        Palee.Finance.PackageRequestStore.get(request.id)
      end)

    assert stored.first_class_scheduled_class_id == first.id
    assert %DateTime{} = stored.first_class_at
  end

  test "«Απόρριψη» needs a reason, the person hears it and their waiting class goes", ctx do
    package = start_rule(ctx)
    {user, context} = newcomer(ctx, "rule_declined")
    {:ok, %{request: request}} = PackageRequests.request(context, package.id)
    {:ok, booking} = book(context, user, slot(ctx))

    assert {:error, :package_decline_reason_required} =
             PackageRequests.decline(ctx.owner_context, request.id, ctx.owner.id, %{
               "reason" => "  "
             })

    assert {:ok, %{request: declined, cancelled_bookings: 1}} =
             PackageRequests.decline(ctx.owner_context, request.id, ctx.owner.id, %{
               "reason" => "Δεν ήρθες στο πρώτο μάθημα"
             })

    assert declined.status == "declined"
    assert declined.decline_reason == "Δεν ήρθες στο πρώτο μάθημα"

    refute Finance.with_tenant_context(ctx.owner_context, fn ->
             Repo.get(Palee.Scheduling.Booking, booking.id)
           end)

    assert_enqueued(
      worker: Palee.Workers.NotificationEventJob,
      args: %{"event" => "package_request_declined"}
    )

    assert {:error, :package_request_closed} =
             PackageRequests.decline(ctx.owner_context, request.id, ctx.owner.id, %{
               "reason" => "again"
             })
  end

  test "«Εκκρεμεί πληρωμή» starts the package now and leaves its charge owed", ctx do
    package = start_rule(ctx)
    {user, context} = newcomer(ctx, "rule_unpaid")
    {:ok, %{request: request}} = PackageRequests.request(context, package.id)

    assert {:ok, %{request: activated, subscription_id: subscription_id}} =
             PackageRequests.activate_unpaid(ctx.owner_context, request.id, ctx.owner.id)

    assert activated.status == "activated"
    assert is_binary(subscription_id)

    membership = Finance.get_member_profile(ctx.owner_context, user.id).membership
    assert Finance.membership_outstanding_balance_cents(ctx.owner_context, membership.id) == 6_000

    # A retry finds it closed.
    assert {:error, :package_request_closed} =
             PackageRequests.activate_unpaid(ctx.owner_context, request.id, ctx.owner.id)

    assert {:ok, _booking} = book(context, user, slot(ctx))
    assert {:ok, _booking} = book(context, user, slot(ctx))
  end

  test "a new «Το θέλω» tells the staff who take payments", ctx do
    package = start_rule(ctx)
    {_user, context} = newcomer(ctx, "rule_notified")
    {:ok, _result} = PackageRequests.request(context, package.id)

    assert_enqueued(
      worker: Palee.Workers.NotificationEventJob,
      args: %{"event" => "package_requested"}
    )
  end

  test "the four notifications reach their people in their words", ctx do
    {user, _context} = newcomer(ctx, "rule_words")
    org = ctx.organization.id

    :ok =
      Palee.Notifications.process_event("package_requested", %{
        organization_id: org,
        package_request_id: Ecto.UUID.generate(),
        member_user_id: user.id,
        person_nickname: "rule_words",
        package_name: "Μηνιαίο"
      })

    :ok =
      Palee.Notifications.process_event("package_rule_started", %{
        organization_id: org,
        count: 3,
        ends_on: "2027-01-14"
      })

    :ok =
      Palee.Notifications.process_event("package_request_declined", %{
        organization_id: org,
        user_id: user.id,
        package_request_id: Ecto.UUID.generate(),
        package_name: "Μηνιαίο",
        reason: "Λάθος πακέτο",
        box_name: "Rule Gym",
        box_slug: "rule"
      })

    :ok =
      Palee.Notifications.process_event("package_rule_grace", %{
        organization_id: org,
        user_id: user.id,
        ends_on: "2027-01-14",
        box_name: "Rule Gym",
        box_slug: "rule"
      })

    staff_types =
      ctx.owner.id |> Palee.Notifications.list_for_user() |> Enum.map(&to_string(&1.type))

    assert "package_requested" in staff_types
    assert "package_rule_started" in staff_types

    mine = Palee.Notifications.list_for_user(user.id)
    declined = Enum.find(mine, &(to_string(&1.type) == "package_request_declined"))
    assert declined.payload["reason"] == "Λάθος πακέτο"
    assert declined.payload["title"]
    assert Enum.any?(mine, &(to_string(&1.type) == "package_rule_grace"))
  end

  test "staff placing someone are not stopped by the rule", ctx do
    start_rule(ctx)
    {user, _context} = newcomer(ctx, "rule_placed")

    assert {:ok, _placed} =
             PlaceMemberInClass.call(ctx.owner_context, user.id, %{slot_id: slot(ctx).id})
  end

  test "a box that stops selling packages stops the rule", ctx do
    package = start_rule(ctx)
    {:ok, _archived} = Finance.update_package(ctx.owner_context, package.id, %{active: false})

    assert PackageRule.daily(%{organization_id: ctx.organization.id}) == :stopped
    {user, context} = newcomer(ctx, "rule_after_stop")
    assert {:ok, _booking} = book(context, user, slot(ctx))
  end
end
