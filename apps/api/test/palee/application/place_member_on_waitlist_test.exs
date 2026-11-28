defmodule Palee.Application.PlaceMemberOnWaitlistTest do
  @moduledoc "ADR-790: staff put a member on a full class's waitlist."
  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  alias Oban.Testing

  alias Palee.Application.{
    GetClassPlacementOptions,
    JoinClassWaitlist,
    PlaceMemberInClass,
    PlaceMemberOnWaitlist,
    SubmitBooking,
    WithdrawBooking
  }

  alias Palee.{Finance, Notifications, Organizations, Scheduling}
  alias Palee.Scheduling.Booking

  import Palee.TestFixtures

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture()
    admin_context = tenant_context(admin, :owner)
    workout = workout_fixture(admin)

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    %{admin: admin, admin_context: admin_context, workout: workout}
  end

  defp tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  defp member(visits \\ 10) do
    {:ok, package} =
      Finance.create_package(%{
        name: "Package #{System.unique_integer([:positive])}",
        package_type: "class_pack",
        fields: %{
          "group_classes.visits" => %{"limit" => visits, "period" => "subscription_period"}
        }
      })

    user = user_fixture()
    context = tenant_context(user)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})
    {user, context}
  end

  defp hours_from_now(hours),
    do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(hours * 3600, :second)

  # A full class that asks for approval: a staff entry is still approved.
  defp full_class(admin_context, workout, attrs \\ %{}) do
    {taker, taker_context} = member()

    slot =
      slot_fixture(
        workout,
        Map.merge(%{capacity: 1, auto_approve: false, scheduled_at: hours_from_now(5)}, attrs)
      )

    {:ok, %{booking: booking}} =
      PlaceMemberInClass.call(admin_context, taker.id, %{slot_id: slot.id})

    %{slot: slot, taker: taker, taker_context: taker_context, booking: booking}
  end

  defp order(context, slot_id) do
    context
    |> Scheduling.list_waitlist(slot_id)
    |> Palee.Scheduling.Domain.BookingPolicy.waitlist_order()
    |> Enum.map(& &1.user_id)
  end

  test "staff put members at the end or first in line, and the member hears it", %{
    admin: admin,
    admin_context: admin_context,
    workout: workout
  } do
    Testing.with_testing_mode(:manual, fn ->
      %{slot: slot} = full_class(admin_context, workout)
      {early, early_context} = member()
      {late, _} = member()
      {front, _} = member()

      assert {:ok, %{status: :waitlisted}} = JoinClassWaitlist.call(early_context, early, slot.id)

      assert {:ok, %{booking: entry, waitlist_position: 2}} =
               PlaceMemberOnWaitlist.call(admin_context, late.id, %{
                 slot_id: slot.id,
                 position: "end"
               })

      assert entry.status == :waitlisted
      assert Repo.get!(Booking, entry.id).waitlisted_by_id == admin.id

      assert {:ok, %{waitlist_position: 1}} =
               PlaceMemberOnWaitlist.call(admin_context, front.id, %{
                 "slot_id" => slot.id,
                 "position" => "first"
               })

      assert order(admin_context, slot.id) == [front.id, early.id, late.id]

      Oban.drain_queue(queue: :notifications, with_safety: false)

      notice =
        late.id
        |> Notifications.list_for_user()
        |> Enum.find(&(&1.type == "booking_waitlisted_by_staff"))

      assert notice.payload["scheduled_class_id"] == slot.id
      assert notice.payload["position"] == 2
    end)
  end

  test "a place from a staff entry is approved at once, even where the class asks for approval",
       %{admin_context: admin_context, workout: workout} do
    %{slot: slot, taker: taker, taker_context: taker_context, booking: booking} =
      full_class(admin_context, workout)

    {waiting, _} = member()

    assert {:ok, _} =
             PlaceMemberOnWaitlist.call(admin_context, waiting.id, %{slot_id: slot.id})

    assert {:ok, _withdrawn} = WithdrawBooking.call(taker_context, taker.id, booking.id)

    statuses =
      admin_context
      |> Scheduling.get_slot(slot.id)
      |> Map.fetch!(:bookings)
      |> Map.new(&{&1.user_id, &1.status})

    assert statuses[waiting.id] == :approved
    assert Repo.get_by!(Booking, user_id: waiting.id).waitlist_front_at == nil
  end

  test "refuses a class with room, a second entry, a wrong position and non-members", %{
    admin_context: admin_context,
    workout: workout
  } do
    %{slot: slot, taker: taker} = full_class(admin_context, workout)
    open = slot_fixture(workout, %{capacity: 5, auto_approve: true})
    {waiting, _} = member()

    assert {:error, :slot_not_full} =
             PlaceMemberOnWaitlist.call(admin_context, waiting.id, %{slot_id: open.id})

    assert {:error, :already_booked} =
             PlaceMemberOnWaitlist.call(admin_context, taker.id, %{slot_id: slot.id})

    assert {:error, :invalid_waitlist_position} =
             PlaceMemberOnWaitlist.call(admin_context, waiting.id, %{
               slot_id: slot.id,
               position: "middle"
             })

    athlete = user_fixture()
    tenant_context(athlete, :athlete)

    assert {:error, :class_placement_requires_member} =
             PlaceMemberOnWaitlist.call(admin_context, athlete.id, %{slot_id: slot.id})
  end

  test "the package is checked as for a staff placement", %{
    admin_context: admin_context,
    workout: workout
  } do
    %{slot: slot} = full_class(admin_context, workout)
    {spent, spent_context} = member(1)
    elsewhere = slot_fixture(workout, %{capacity: 5, auto_approve: true})
    assert {:ok, _} = SubmitBooking.call(spent_context, spent, elsewhere.id)

    assert {:error, :finance_allowance_exhausted} =
             PlaceMemberOnWaitlist.call(admin_context, spent.id, %{slot_id: slot.id})
  end

  test "a coach adds people to the classes they run, not to others", %{
    admin_context: admin_context,
    workout: workout
  } do
    coach = user_fixture()
    coach_context = tenant_context(coach, :coach)
    %{slot: own} = full_class(admin_context, workout, %{coach_user_id: coach.id})
    %{slot: other} = full_class(admin_context, workout)
    roomy = slot_fixture(workout, %{capacity: 5, auto_approve: true, coach_user_id: coach.id})
    {waiting, _} = member()

    assert {:ok, _} = PlaceMemberOnWaitlist.call(coach_context, waiting.id, %{slot_id: own.id})

    assert {:error, :forbidden} =
             PlaceMemberOnWaitlist.call(coach_context, waiting.id, %{slot_id: other.id})

    # The profile's whole list stays with staff who book for clients.
    assert {:error, :forbidden} = GetClassPlacementOptions.call(coach_context, waiting.id)

    assert {:ok, %{classes: [%{slot_id: slot_id, waitlist: false}]}} =
             GetClassPlacementOptions.call(coach_context, waiting.id, slot_id: roomy.id)

    assert slot_id == roomy.id

    assert {:ok, %{booking: %{status: :approved}}} =
             PlaceMemberInClass.call(coach_context, waiting.id, %{slot_id: roomy.id})
  end

  test "the profile's choices offer a full class's waitlist with the place it gives", %{
    admin_context: admin_context,
    workout: workout
  } do
    %{slot: slot} = full_class(admin_context, workout)
    {early, early_context} = member()
    {waiting, _} = member()
    assert {:ok, _} = JoinClassWaitlist.call(early_context, early, slot.id)

    assert {:ok, %{classes: classes}} = GetClassPlacementOptions.call(admin_context, waiting.id)
    option = Enum.find(classes, &(&1.slot_id == slot.id))

    assert %{blocked_reason: nil, waitlist: true, waitlist_place: 2} = option

    # Far away classes are reached one at a time from the class page.
    far = slot_fixture(workout, %{capacity: 5, scheduled_at: hours_from_now(24 * 45)})

    assert {:ok, %{classes: [%{slot_id: far_id}]}} =
             GetClassPlacementOptions.call(admin_context, waiting.id, slot_id: far.id)

    assert far_id == far.id
  end
end
