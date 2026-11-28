defmodule Palee.Application.ClassVariantsTest do
  @moduledoc """
  ADR-785: a member's «Παραλλαγή» of one class. It needs no online
  programming, starts from the WOD the member does, is made only until the
  class ends, replaces the member's earlier one, tells the roster when the
  class WOD changed after it, lets the member go back to the class's WODs,
  and goes away with a cancelled class.
  """
  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Repo
  alias Palee.Scheduling.ScheduledClass

  alias Palee.{Finance, Organizations, Scheduling, Workouts}

  alias Palee.Application.{
    AuthorizeFinanceEntitlement,
    ClassVariants,
    GetScheduleCalendar,
    ProgramUserWorkout
  }

  @class_only_plan %{
    "entitlement_version" => 1,
    "channels" => ["in_person"],
    "capabilities" => ["book_classes", "execute_class_workouts"],
    "allowances" => %{}
  }

  defp tenant(name) do
    admin = admin_fixture(%{nickname: "#{name}_admin_#{System.unique_integer([:positive])}"})
    {:ok, organization} = Organizations.create_organization(%{name: "#{name} Gym"})
    add_membership(organization, admin, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)
    %{admin: admin, organization: organization, context: context}
  end

  defp add_membership(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp member(gym, nickname) do
    user =
      %{nickname: "#{nickname}_#{System.unique_integer([:positive])}", role: :member}
      |> user_fixture()
      |> then(&add_membership(gym.organization, &1, :member))

    {:ok, package} =
      Finance.create_package(gym.context, %{
        code: "adr785-#{System.unique_integer([:positive])}",
        name: "Class only",
        family: "hybrid",
        billing_period: "monthly",
        params: @class_only_plan
      })

    {:ok, membership} =
      Finance.upsert_membership(gym.context, user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _subscription} =
      Finance.assign_package(gym.context, membership.id, package.id, %{
        starts_on: Date.utc_today()
      })

    user
  end

  defp class(gym, workout, members, starts_in_seconds \\ 2 * 3600) do
    class_type = class_type_fixture(%{tenant_context: gym.context})

    slot =
      slot_fixture(workout, %{
        tenant_context: gym.context,
        class_type_id: class_type.id,
        auto_approve: true,
        duration_minutes: 60,
        scheduled_at: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)
      })

    Enum.each(members, fn member ->
      {:ok, _booking} = Scheduling.submit_auto_approved_booking(gym.context, member.id, slot.id)
    end)

    # A class already running or over: moved back once its bookings are in.
    at = DateTime.utc_now() |> DateTime.add(starts_in_seconds) |> DateTime.truncate(:second)

    {1, _} =
      ScheduledClass
      |> where([class], class.id == ^slot.id)
      |> Repo.update_all(set: [scheduled_at: at])

    %{slot | scheduled_at: at}
  end

  defp day(slot), do: slot.scheduled_at |> DateTime.to_date() |> Date.to_iso8601()

  defp variant(gym, member, slot, extra \\ %{}) do
    ProgramUserWorkout.call(
      gym.context,
      gym.admin,
      member.id,
      Map.merge(%{scheduled_for: day(slot), slot_id: slot.id, copy_source: true}, extra)
    )
  end

  defp variants(gym, slot), do: Workouts.list_class_variants(gym.context, [slot.id], nil)

  test "a class-only member gets a variant without online programming; no mode means a variant" do
    gym = tenant("cv_plain")
    maria = member(gym, "cv_maria")
    wod = workout_fixture(gym.admin, %{title: "Fran", tenant_context: gym.context})
    slot = class(gym, wod, [maria])

    assert {:ok, %{mode: "class_variant", association: association}} = variant(gym, maria, slot)
    assert association.source_slot_id == slot.id

    assert [%{assignee_id: assignee_id} = stored] = variants(gym, slot)
    assert assignee_id == maria.id
    assert stored.variant_of_workout_id == wod.id
    assert is_binary(stored.variant_source_hash)
    assert stored.assigned_by_user_id == gym.admin.id
    assert is_nil(stored.set_aside_at)

    # The class keeps its own WOD for everyone else.
    assert Scheduling.get_slot(gym.context, slot.id).master_workout_id == wod.id
  end

  test "a class that has ended takes no variant; one still running does" do
    gym = tenant("cv_closed")
    maria = member(gym, "cv_closed_maria")
    wod = workout_fixture(gym.admin, %{title: "Ended WOD", tenant_context: gym.context})

    ended = class(gym, wod, [], -2 * 3600)
    assert {:error, :class_variant_closed} = variant(gym, maria, ended, %{offer_booking: true})

    running = class(gym, wod, [maria], -20 * 60)
    assert {:ok, %{mode: "class_variant"}} = variant(gym, maria, running)
  end

  test "a new variant replaces the member's earlier one of the same class" do
    gym = tenant("cv_replace")
    maria = member(gym, "cv_replace_maria")
    nikos = member(gym, "cv_replace_nikos")
    wod = workout_fixture(gym.admin, %{title: "Replace WOD", tenant_context: gym.context})
    slot = class(gym, wod, [maria, nikos])

    assert {:ok, _first} = variant(gym, maria, slot)
    assert {:ok, _nikos} = variant(gym, nikos, slot)
    assert {:ok, %{association: second}} = variant(gym, maria, slot, %{instructions: "Ώμος"})

    marias = Enum.filter(variants(gym, slot), &(&1.assignee_id == maria.id))
    assert [%{assignment_id: id, instructions: "Ώμος"}] = marias
    assert id == second.id
    assert Enum.any?(variants(gym, slot), &(&1.assignee_id == nikos.id))
  end

  test "the roster says when the class WOD changed after the variant, until «Κράτησέ τη»" do
    gym = tenant("cv_stale")
    maria = member(gym, "cv_stale_maria")
    wod = workout_fixture(gym.admin, %{title: "Stale WOD", tenant_context: gym.context})
    slot = class(gym, wod, [maria])
    assert {:ok, %{association: association}} = variant(gym, maria, slot)

    assert staff_version(gym, slot).stale == nil

    # As if the class WOD read differently when the variant was made.
    {:ok, _} =
      Workouts.update_class_variant(gym.context, association.id, %{variant_source_hash: "old"})

    assert staff_version(gym, slot).stale == "changed"

    assert :ok = ClassVariants.keep(gym.context, slot.id, association.id)
    assert staff_version(gym, slot).stale == nil
  end

  test "the member goes back to the class's WODs and to their variant again" do
    gym = tenant("cv_aside")
    maria = member(gym, "cv_aside_maria")
    wod = workout_fixture(gym.admin, %{title: "Aside WOD", tenant_context: gym.context})
    slot = class(gym, wod, [maria])
    assert {:ok, _} = variant(gym, maria, slot)

    member_context = Map.put(gym.context, :user_id, maria.id)
    assert :ok = ClassVariants.set_active(member_context, maria, slot.id, false)
    assert [%{set_aside_at: %DateTime{}}] = variants(gym, slot)
    assert :ok = ClassVariants.set_active(member_context, maria, slot.id, true)
    assert [%{set_aside_at: nil}] = variants(gym, slot)

    other = member(gym, "cv_aside_other")

    assert {:error, :class_variant_not_found} =
             ClassVariants.set_active(gym.context, other, slot.id, false)
  end

  test "a cancelled class takes its variants with it" do
    gym = tenant("cv_cancel")
    maria = member(gym, "cv_cancel_maria")
    wod = workout_fixture(gym.admin, %{title: "Cancel WOD", tenant_context: gym.context})
    slot = class(gym, wod, [maria])
    assert {:ok, _} = variant(gym, maria, slot)

    assert :ok =
             ClassVariants.handle_event(:class_cancelled, %{
               organization_id: gym.organization.id,
               scheduled_class_id: slot.id
             })

    assert variants(gym, slot) == []
  end

  test "doing a class variant needs what the class needs, not online programming" do
    assert AuthorizeFinanceEntitlement.execution_request(%{
             source: "assigned",
             class_variant: true
           }) == %{capability: :execute_class_workouts}

    assert AuthorizeFinanceEntitlement.execution_request(%{source: "assigned"}) ==
             %{channel: :personal_programming, capability: :execute_assigned_workouts}
  end

  defp staff_version(gym, slot) do
    date = slot.scheduled_at |> DateTime.to_date()

    {:ok, %{slots: slots}} =
      GetScheduleCalendar.call(gym.context, gym.admin, %{
        "start_date" => date |> Date.add(-1) |> Date.to_iso8601(),
        "days" => "3"
      })

    slots
    |> Enum.find(&(&1.id == slot.id))
    |> Map.fetch!(:member_versions)
    |> List.first()
  end
end
