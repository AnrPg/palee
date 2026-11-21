defmodule Palee.Application.AdminRemoveAttendanceTest do
  use Palee.DataCase

  alias Palee.Application.{AdminRecordAttendance, AdminRemoveAttendance}
  alias Palee.{Organizations, Scheduling}
  alias Palee.TestFixtures

  setup do
    {:ok, legacy_organization} = Organizations.ensure_legacy_organization_for_migration()

    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      legacy_organization.id
    ])

    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture()
    context = legacy_tenant_context(admin, :owner)
    legacy_tenant_context(member)
    workout = TestFixtures.workout_fixture(admin)
    slot = TestFixtures.slot_fixture(workout, %{auto_approve: true})
    {:ok, booking} = Scheduling.submit_auto_approved_booking(context, member.id, slot.id)

    %{admin: admin, member: member, context: context, slot: slot, booking: booking}
  end

  defp legacy_tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  test "takes back «Ήρθε»: the record goes, the booking stays, and the class page is told",
       %{admin: admin, member: member, context: context, slot: slot, booking: booking} do
    assert {:ok, _attendance} =
             AdminRecordAttendance.call(context, slot.id, member.id, admin.id, %{
               status: "attended"
             })

    Phoenix.PubSub.subscribe(Palee.PubSub, "schedule:#{context.organization_id}")

    assert {:ok, %{status: "attended"}} =
             AdminRemoveAttendance.call(context, slot.id, member.id, admin.id)

    refute Scheduling.get_attendance_for_user_class(context, member.id, slot.id)

    assert %{id: booking_id} =
             Scheduling.get_approved_booking_for_class(context, member.id, slot.id)

    assert booking_id == booking.id

    assert_receive %Phoenix.Socket.Broadcast{
      event: "schedule:refresh",
      payload: %{event: "attendance_removed", payload: payload}
    }

    assert payload.slot_id == slot.id
    refute Map.has_key?(payload, :user_id)

    # «Ήρθε» can be recorded again afterwards.
    assert {:ok, %{status: "attended"}} =
             AdminRecordAttendance.call(context, slot.id, member.id, admin.id, %{
               status: "attended"
             })
  end

  test "only «Ήρθε» can be taken back", %{
    admin: admin,
    member: member,
    context: context,
    slot: slot
  } do
    assert {:ok, _attendance} =
             AdminRecordAttendance.call(context, slot.id, member.id, admin.id, %{
               status: "no_show"
             })

    assert {:error, :attendance_not_removable} =
             AdminRemoveAttendance.call(context, slot.id, member.id, admin.id)

    assert %{status: "no_show"} =
             Scheduling.get_attendance_for_user_class(context, member.id, slot.id)
  end

  test "nothing to take back without a recorded attendance",
       %{admin: admin, member: member, context: context, slot: slot} do
    assert {:error, :not_found} =
             AdminRemoveAttendance.call(context, slot.id, member.id, admin.id)
  end
end
