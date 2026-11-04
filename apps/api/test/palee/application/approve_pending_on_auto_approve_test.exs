defmodule Palee.Application.ApprovePendingOnAutoApproveTest do
  @moduledoc "ADR-226 follow-up: turning automatic confirmation on answers the waiting requests."
  use Palee.DataCase, async: false

  import Palee.AnalyticsHelpers

  alias Palee.Application.{CreateScheduledSlot, SubmitBooking, UpdateScheduledSlot}
  alias Palee.{Scheduling, TestFixtures}

  defp slot!(context, owner, capacity) do
    workout = TestFixtures.workout_fixture(owner, %{tenant_context: context})
    class_type = TestFixtures.class_type_fixture(%{tenant_context: context})

    {:ok, slot} =
      CreateScheduledSlot.call(context, %{
        master_workout_id: workout.id,
        class_type_id: class_type.id,
        scheduled_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 7200),
        capacity: capacity,
        auto_approve: false,
        booking_timeout_minutes: 60
      })

    slot
  end

  defp request!(organization, slot) do
    {member, member_context} = member_context(organization)
    {:ok, booking} = SubmitBooking.call(member_context, member, slot.id)
    assert booking.status == :pending
    booking
  end

  # The class editor always sends the type and the workout with an edit.
  defp edit(context, slot, changes),
    do:
      UpdateScheduledSlot.call(
        context,
        slot.id,
        Map.merge(
          %{class_type_id: slot.class_type_id, master_workout_id: slot.master_workout_id},
          changes
        )
      )

  defp status(context, booking), do: Scheduling.get_booking(context, booking.id).status

  test "waiting requests are approved in the order they were made, while seats last" do
    {organization, owner, context} = organization_fixture()
    slot = slot!(context, owner, 2)
    first = request!(organization, slot)
    second = request!(organization, slot)

    # One seat left after the edit: only the earliest request fits.
    assert {:ok, _slot} = edit(context, slot, %{capacity: 1, auto_approve: true})

    assert status(context, first) == :approved
    assert status(context, second) == :pending
  end

  test "every waiting request is approved when seats are free" do
    {organization, owner, context} = organization_fixture()
    slot = slot!(context, owner, 5)
    requests = for _ <- 1..3, do: request!(organization, slot)

    assert {:ok, updated} = edit(context, slot, %{auto_approve: true})

    assert updated.auto_approve
    assert Enum.all?(requests, &(status(context, &1) == :approved))
  end

  test "other edits leave waiting requests alone" do
    {organization, owner, context} = organization_fixture()
    slot = slot!(context, owner, 5)
    request = request!(organization, slot)

    assert {:ok, _slot} = edit(context, slot, %{capacity: 6})

    assert status(context, request) == :pending
  end
end
