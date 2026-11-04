defmodule Palee.Application.AuthorizeWodAccessTest do
  @moduledoc "ADR-551: no workouts for a member whose access has closed."
  use Palee.DataCase, async: false

  alias Palee.Application.{
    AuthorizeWodAccess,
    GetAssignedWorkoutWeek,
    GetScheduleCalendar
  }

  alias Palee.Finance.Domain.EntitlementPolicy
  alias Palee.{Finance, Organizations}

  import Palee.TestFixtures

  setup do
    {:ok, legacy_organization} = Organizations.ensure_legacy_organization_for_migration()

    Palee.Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      legacy_organization.id
    ])

    :ok
  end

  defp legacy_tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  defp close_access(member) do
    {:ok, _membership} =
      Finance.upsert_membership(member.id, %{
        user_type_snapshot: "member",
        status: "paused",
        signup_source: "direct"
      })
  end

  describe "EntitlementPolicy.access_open/1" do
    test "closes only on blocked or inactive" do
      assert EntitlementPolicy.access_open(nil) == :ok
      assert EntitlementPolicy.access_open(%{status: "active"}) == :ok
      assert EntitlementPolicy.access_open(%{status: "grace"}) == :ok

      assert EntitlementPolicy.access_open(%{status: "blocked"}) ==
               {:error, :finance_entitlement_blocked}

      assert EntitlementPolicy.access_open(%{status: "inactive"}) ==
               {:error, :finance_entitlement_inactive}

      # A package bought ahead keeps it open before its first day.
      assert EntitlementPolicy.access_open(%{
               status: "inactive",
               source: "no_active_package",
               upcoming_starts_on: ~D[2026-12-01]
             }) == :ok

      assert EntitlementPolicy.access_open(%{
               status: "inactive",
               source: "membership_status",
               upcoming_starts_on: ~D[2026-12-01]
             }) == {:error, :finance_entitlement_inactive}
    end
  end

  test "a gym without finance keeps everything open" do
    member = user_fixture()
    context = legacy_tenant_context(member)

    assert AuthorizeWodAccess.call(context, member.id) == :ok
  end

  test "a member whose access closed gets no programme and no class WODs" do
    admin = admin_fixture()
    member = user_fixture()
    admin_context = legacy_tenant_context(admin, :owner)
    context = legacy_tenant_context(member)
    workout = workout_fixture(admin)
    slot = slot_fixture(workout, %{auto_approve: true})
    close_access(member)

    assert AuthorizeWodAccess.call(context, member.id) == {:error, :finance_entitlement_inactive}

    assert GetAssignedWorkoutWeek.call(context, member, %{}) ==
             {:error, :finance_entitlement_inactive}

    params = %{"start_date" => slot.scheduled_at |> DateTime.to_date() |> Date.to_iso8601()}

    assert {:ok, %{slots: slots}} = GetScheduleCalendar.call(context, member, params)
    locked = Enum.find(slots, &(&1.id == slot.id))
    assert locked.wod_locked
    assert locked.workout == nil
    assert locked.my_version == nil

    # Staff are never gated.
    assert AuthorizeWodAccess.call(admin_context, admin.id) == :ok
    assert {:ok, %{slots: staff_slots}} = GetScheduleCalendar.call(admin_context, admin, params)
    shown = Enum.find(staff_slots, &(&1.id == slot.id))
    refute shown.wod_locked
    assert shown.workout.id == workout.id
  end
end
