defmodule PaleeWeb.ClassMultipleWorkoutsTest do
  @moduledoc "ADR-746: several WODs in one class, «Τώρα», and who does which."

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures, only: [slot_fixture: 2, workout_fixture: 2]

  alias Palee.{Identity, Organizations, Repo}
  alias Palee.Scheduling.Booking

  setup %{conn: conn} do
    admin = create_user!(:owner, "multi_wod_coach")
    member = create_user!(:member, "multi_wod_member")
    other = create_user!(:member, "multi_wod_other")

    {:ok, context} =
      Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

    first = workout_fixture(admin, %{tenant_context: context, title: "Fran"})
    second = workout_fixture(admin, %{tenant_context: context, title: "Cindy"})
    third = workout_fixture(admin, %{tenant_context: context, title: "Helen"})
    slot = slot_fixture(first, %{tenant_context: context})

    booking =
      Repo.insert!(%Booking{
        organization_id: slot.organization_id,
        scheduled_class_id: slot.id,
        user_id: member.id,
        status: :approved
      })

    {:ok,
     coach: put_bearer_token(conn, admin),
     member: put_bearer_token(conn, member),
     other: put_bearer_token(conn, other),
     slot: slot,
     booking: booking,
     first: first,
     second: second,
     third: third}
  end

  defp path(suffix), do: "/api/org/#{Organizations.legacy_organization_slug()}#{suffix}"

  defp set_workouts(conn, slot, ids),
    do: put(conn, path("/admin/schedule/slots/#{slot.id}/workouts"), %{workout_ids: ids})

  # New WODs are filed as the class's own copies (ADR-680), so the ids come
  # back from the saved class.
  defp saved_ids(conn, slot, ids) do
    saved = conn |> set_workouts(slot, ids) |> json_response(200) |> Map.fetch!("slot")
    [saved["master_workout_id"] | saved["additional_workout_ids"]]
  end

  defp titles(listed), do: Enum.map(listed["workouts"], & &1["title"])

  defp my_slot(conn, slot) do
    start_at = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)
    end_at = DateTime.add(start_at, 2 * 86_400, :second)

    conn
    |> get(
      path(
        "/schedule?start_at=#{URI.encode_www_form(DateTime.to_iso8601(start_at))}" <>
          "&end_at=#{URI.encode_www_form(DateTime.to_iso8601(end_at))}&days=3"
      )
    )
    |> json_response(200)
    |> Map.fetch!("slots")
    |> Enum.find(&(&1["id"] == slot.id))
  end

  test "staff add WODs in order; the first stays the class's WOD", ctx do
    %{coach: coach, slot: slot, first: first, second: second, third: third} = ctx

    [a, b, c] = saved_ids(coach, slot, [first.id, second.id, third.id])
    assert a == first.id

    listed = my_slot(ctx.member, slot)
    assert Enum.map(listed["workouts"], & &1["id"]) == [a, b, c]
    assert titles(listed) == [first.title, second.title, third.title]
    assert listed["live_workout_id"] == a
    assert listed["current_user_booking"]["chosen_workout_id"] == nil

    assert [^b, ^a] = saved_ids(coach, slot, [b, a])
    assert titles(my_slot(ctx.member, slot)) == [second.title, first.title]
  end

  test "a list with a repeated or missing WOD is refused", ctx do
    %{coach: coach, slot: slot, first: first} = ctx

    assert coach |> set_workouts(slot, []) |> json_response(422)
    assert coach |> set_workouts(slot, [first.id, first.id]) |> json_response(422)
  end

  test "members are not allowed to change the class's WODs", ctx do
    %{member: member, slot: slot, first: first, second: second} = ctx

    status = member |> set_workouts(slot, [first.id, second.id]) |> Map.fetch!(:status)
    assert status in [401, 403]
  end

  test "a member chooses their WOD; a coach can change it; null follows «Τώρα»", ctx do
    %{coach: coach, member: member, slot: slot, booking: booking, first: first, second: second} =
      ctx

    [first_id, second_id] = saved_ids(coach, slot, [first.id, second.id])

    chosen =
      member
      |> put(path("/schedule/slots/#{slot.id}/my-workout"), %{workout_id: second_id})
      |> json_response(200)
      |> Map.fetch!("booking")

    assert chosen["chosen_workout_id"] == second_id
    listed = my_slot(member, slot)
    assert listed["current_user_booking"]["chosen_workout_id"] == second_id
    assert listed["current_user_booking"]["workout_chosen_by_coach"] == false

    assert %{"undecided" => 0, "workouts" => counts} = listed["workout_choice_counts"]
    assert Enum.find(counts, &(&1["workout_id"] == second_id))["count"] == 1

    by_coach =
      coach
      |> put(
        path("/admin/schedule/slots/#{slot.id}/bookings/#{booking.id}/workout"),
        %{workout_id: first_id}
      )
      |> json_response(200)
      |> Map.fetch!("booking")

    assert by_coach["chosen_workout_id"] == first_id
    assert my_slot(member, slot)["current_user_booking"]["workout_chosen_by_coach"] == true

    back =
      member
      |> put(path("/schedule/slots/#{slot.id}/my-workout"), %{workout_id: nil})
      |> json_response(200)
      |> Map.fetch!("booking")

    assert back["chosen_workout_id"] == nil
  end

  test "a WOD that is not one of the class's is refused", ctx do
    %{member: member, slot: slot, third: third} = ctx

    assert %{"code" => "not_a_class_workout"} =
             member
             |> put(path("/schedule/slots/#{slot.id}/my-workout"), %{workout_id: third.id})
             |> json_response(422)
  end

  test "someone without a booking cannot choose", ctx do
    %{coach: coach, other: other, slot: slot, first: first, second: second} = ctx
    [_first_id, second_id] = saved_ids(coach, slot, [first.id, second.id])

    assert other
           |> put(path("/schedule/slots/#{slot.id}/my-workout"), %{workout_id: second_id})
           |> json_response(404)
  end

  test "«Τώρα» moves, and removing that WOD sends «Τώρα» and its people back", ctx do
    %{coach: coach, member: member, slot: slot, first: first, second: second} = ctx
    [first_id, second_id] = saved_ids(coach, slot, [first.id, second.id])

    live =
      coach
      |> put(path("/admin/schedule/slots/#{slot.id}/live-workout"), %{workout_id: second_id})
      |> json_response(200)
      |> Map.fetch!("slot")

    assert live["live_workout_id"] == second_id

    member
    |> put(path("/schedule/slots/#{slot.id}/my-workout"), %{workout_id: second_id})
    |> json_response(200)

    coach |> set_workouts(slot, [first_id]) |> json_response(200)

    listed = my_slot(member, slot)
    assert listed["live_workout_id"] == first_id
    assert listed["current_user_booking"]["chosen_workout_id"] == nil
  end

  test "the class timer follows «Τώρα» and each WOD keeps its own clock", ctx do
    %{coach: coach, member: member, slot: slot, first: first, second: second} = ctx
    [first_id, second_id] = saved_ids(coach, slot, [first.id, second.id])
    base = path("/class-timers/#{slot.id}")

    now = member |> get(base) |> json_response(200)
    assert now["workout"]["id"] == first_id
    assert now["live_workout_id"] == first_id
    assert Enum.map(now["workouts"], & &1["id"]) == [first_id, second_id]

    started =
      coach
      |> post("#{base}/commands", %{
        command: "start",
        countdown_seconds: 0,
        expected_version: now["timer"]["lock_version"]
      })
      |> json_response(200)

    assert started["timer"]["status"] == "running"

    other = member |> get("#{base}?workout_id=#{second_id}") |> json_response(200)
    assert other["workout"]["id"] == second_id
    assert other["timer"]["status"] == "ready"
    assert other["live"] == false

    coach
    |> put(path("/admin/schedule/slots/#{slot.id}/live-workout"), %{workout_id: second_id})
    |> json_response(200)

    moved = member |> get(base) |> json_response(200)
    assert moved["workout"]["id"] == second_id

    assert [%{"status" => "running"}] =
             Enum.filter(moved["other_timers"], &(&1["workout_id"] == first_id))
  end

  defp create_user!(role, nickname) do
    {:ok, user} =
      Identity.register(%{
        nickname: "#{nickname}_#{System.unique_integer([:positive])}",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    user =
      if role == :owner do
        {:ok, admin} = Identity.update_role(user, :admin)
        admin
      else
        user
      end

    {:ok, _membership} =
      if role == :owner,
        do: Organizations.ensure_legacy_membership_for_migration(user, :owner),
        else: Organizations.ensure_legacy_membership_for_migration(user)

    user
  end
end
