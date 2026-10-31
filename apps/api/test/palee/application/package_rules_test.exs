defmodule Palee.Application.PackageRulesTest do
  @moduledoc """
  ADR-342 (CP-A8) through the real stores: a package's booking limits are
  enforced by SubmitBooking and its purchase rules by Finance.
  """
  use Palee.DataCase, async: false

  alias Palee.Application.SubmitBooking
  alias Palee.{Finance, Organizations, Scheduling}

  import Palee.TestFixtures

  setup do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture()
    admin_context = tenant_context(admin, :owner)

    {:ok, _settings} =
      Scheduling.update_settings(admin_context, %{default_booking_window_days: 30})

    %{admin: admin, admin_context: admin_context, workout: workout_fixture(admin)}
  end

  defp tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  defp package(fields) do
    {:ok, package} =
      Finance.create_package(%{
        name: "Package #{System.unique_integer([:positive])}",
        package_type: "membership",
        fields: fields
      })

    package
  end

  defp member do
    user = user_fixture()
    context = tenant_context(user)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {user, context, membership}
  end

  defp member_with(fields) do
    {user, context, membership} = member()
    {:ok, _subscription} = Finance.assign_package(membership.id, package(fields).id, %{})
    {user, context}
  end

  # A class at `time` on the gym-local `date`, stored in UTC.
  defp slot_on(workout, date, time) do
    zone = Palee.TimeZones.ZonedTime.default_zone()
    at = date |> DateTime.new!(time, zone) |> DateTime.shift_zone!("Etc/UTC")
    slot_fixture(workout, %{auto_approve: true, scheduled_at: at})
  end

  # Monday of next week in the gym's time zone, so every class is in the future.
  defp next_monday do
    today = gym_today()
    Date.add(today, 8 - Date.day_of_week(today))
  end

  test "bookings per day and per week are limited by the package", %{workout: workout} do
    {member, context} =
      member_with(%{"booking.daily_limit" => 1, "booking.weekly_limit" => 2})

    monday = next_monday()

    assert {:ok, _} = SubmitBooking.call(context, member, slot_on(workout, monday, ~T[09:00:00]).id)

    assert {:error, :booking_daily_limit_reached, %{limit: 1}} =
             SubmitBooking.call(context, member, slot_on(workout, monday, ~T[18:00:00]).id)

    tuesday = Date.add(monday, 1)
    assert {:ok, _} = SubmitBooking.call(context, member, slot_on(workout, tuesday, ~T[09:00:00]).id)

    assert {:error, :booking_weekly_limit_reached, %{limit: 2}} =
             SubmitBooking.call(
               context,
               member,
               slot_on(workout, Date.add(monday, 3), ~T[09:00:00]).id
             )

    # The next Monday starts a new week.
    assert {:ok, _} =
             SubmitBooking.call(
               context,
               member,
               slot_on(workout, Date.add(monday, 7), ~T[09:00:00]).id
             )
  end

  test "open bookings are limited, and staff placement skips the limits", %{workout: workout} do
    {member, context} = member_with(%{"booking.open_bookings_limit" => 1})
    monday = next_monday()

    assert {:ok, _} = SubmitBooking.call(context, member, slot_on(workout, monday, ~T[09:00:00]).id)

    second = slot_on(workout, Date.add(monday, 2), ~T[09:00:00])

    assert {:error, :booking_open_limit_reached, %{limit: 1}} =
             SubmitBooking.call(context, member, second.id)

    # Staff placing the member (PlaceMemberInClass) are not limited.
    assert {:ok, _booking} =
             Scheduling.transaction(context, fn ->
               with {:ok, _slot, booking} <-
                      SubmitBooking.write(context, member, second.id,
                        approved: true,
                        booking_window: false,
                        documents_gate: false
                      ),
                    do: {:ok, booking}
             end)
  end

  test "purchase rules: staff only, purchases per person and a needed package", %{
    admin_context: admin_context
  } do
    today = gym_today()
    {user, _context, membership} = member()

    staff_only = package(%{"terms.buyers" => "staff_only"})

    assert {:error, :package_staff_only} =
             Finance.purchase_eligibility(admin_context, user.id, staff_only.id, :member, today)

    assert :ok =
             Finance.purchase_eligibility(admin_context, user.id, staff_only.id, :staff, today)

    on_ramp = package(%{})
    after_ramp = package(%{"terms.prerequisite_package_ids" => [on_ramp.id]})

    assert {:error, :package_prerequisite_missing} =
             Finance.purchase_eligibility(admin_context, user.id, after_ramp.id, :member, today)

    {:ok, _} = Finance.assign_package(membership.id, on_ramp.id, %{})

    assert :ok =
             Finance.purchase_eligibility(admin_context, user.id, after_ramp.id, :member, today)

    once = package(%{"terms.max_purchases_per_person" => 1})
    {:ok, _} = Finance.assign_package(membership.id, once.id, %{})

    assert {:error, :package_purchase_limit_reached} =
             Finance.purchase_eligibility(admin_context, user.id, once.id, :member, today)

    assert {:error, :package_purchase_limit_reached} =
             Finance.assign_package(membership.id, once.id, %{})
  end
end
