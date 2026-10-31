defmodule PaleeWeb.CoachPayControllerTest do
  @moduledoc """
  ADR-341 (CP-A6) end to end under row-level security: pay rules, a period
  calculated from the classes a coach led, an adjustment, approval, the CSV
  export and the coach's own statement.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.Organizations
  alias Palee.Scheduling.{ClassAttendanceRecord, ScheduledClass}

  import Palee.TestFixtures

  setup do
    admin = admin_fixture(%{nickname: "pay_admin"})
    coach = user_fixture(%{role: :member, nickname: "pay_coach"})
    {organization, context} = tenant_fixture(admin, "Pay Tenant")
    add_tenant_member(organization, coach, :coach)

    workout = workout_fixture(admin, %{tenant_context: context})
    class_type = class_type_fixture(%{tenant_context: context, name: "WOD"})

    %{
      admin: admin,
      coach: coach,
      organization: organization,
      context: context,
      workout: workout,
      class_type: class_type
    }
  end

  defp path(ctx, rest), do: "/api/org/#{ctx.organization.slug}/admin/coach-pay#{rest}"
  defp as(conn, user), do: put_bearer_token(conn, user)

  defp led_class(ctx, attendees) do
    class =
      Repo.insert!(%ScheduledClass{
        organization_id: ctx.organization.id,
        master_workout_id: ctx.workout.id,
        class_type_id: ctx.class_type.id,
        coach_user_id: ctx.coach.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), -2, :day) |> DateTime.truncate(:second),
        capacity: 10
      })

    for status <- attendees do
      athlete = user_fixture()

      Repo.insert!(%ClassAttendanceRecord{
        organization_id: ctx.organization.id,
        scheduled_class_id: class.id,
        user_id: athlete.id,
        status: status,
        marked_at: DateTime.utc_now()
      })
    end

    class
  end

  defp rule(conn, ctx, body) do
    conn
    |> as(ctx.admin)
    |> post(path(ctx, "/rules"), Map.merge(%{coach_user_id: ctx.coach.id, starts_on: start(-30)}, body))
    |> json_response(201)
  end

  defp start(days), do: Date.utc_today() |> Date.add(days) |> Date.to_iso8601()

  test "a period is calculated, adjusted, approved, exported and shown to the coach",
       %{conn: conn} = ctx do
    led_class(ctx, ["attended", "attended", "no_show"])

    rule(conn, ctx, %{kind: "per_class", amount_cents: 1_500})
    rule(conn, ctx, %{kind: "per_attendee", amount_cents: 200, count_statuses: ["attended"]})

    # A rule for someone who is not a coach of the box is refused.
    outsider = user_fixture()

    assert conn
           |> as(ctx.admin)
           |> post(path(ctx, "/rules"), %{
             coach_user_id: outsider.id,
             kind: "per_class",
             amount_cents: 100,
             starts_on: start(-30)
           })
           |> json_response(422)

    %{"period" => %{"id" => id, "status" => "draft"}} =
      conn
      |> as(ctx.admin)
      |> post(path(ctx, "/periods"), %{starts_on: start(-10), ends_on: start(1)})
      |> json_response(201)

    # Overlapping dates are refused.
    assert %{"code" => "coach_pay_period_overlaps"} =
             conn
             |> as(ctx.admin)
             |> post(path(ctx, "/periods"), %{starts_on: start(-3), ends_on: start(3)})
             |> json_response(409)

    %{"period" => period} =
      conn |> as(ctx.admin) |> post(path(ctx, "/periods/#{id}/calculate")) |> json_response(200)

    [statement] = period["statements"]
    assert statement["coach_user_id"] == ctx.coach.id
    # One class at 15,00 plus two attendees at 2,00 (the no-show does not count).
    assert statement["total_cents"] == 1_900
    assert Enum.sort(Enum.map(statement["lines"], & &1["kind"])) == ["per_attendee", "per_class"]

    %{"period" => period} =
      conn
      |> as(ctx.admin)
      |> post(path(ctx, "/periods/#{id}/adjustments"), %{
        coach_user_id: ctx.coach.id,
        amount_cents: 500,
        description: "Κάλυψη τμήματος"
      })
      |> json_response(200)

    assert [%{"total_cents" => 2_400}] = period["statements"]

    # Calculating again keeps the adjustment.
    %{"period" => period} =
      conn |> as(ctx.admin) |> post(path(ctx, "/periods/#{id}/calculate")) |> json_response(200)

    assert [%{"total_cents" => 2_400}] = period["statements"]

    # The coach sees nothing before approval, and cannot read the admin side.
    assert %{"statements" => []} =
             conn |> as(ctx.coach) |> get(path(ctx, "/mine")) |> json_response(200)

    assert conn |> as(ctx.coach) |> get(path(ctx, "/periods/#{id}")) |> response(403)

    assert %{"code" => "coach_pay_period_not_approved"} =
             conn |> as(ctx.admin) |> get(path(ctx, "/periods/#{id}/export")) |> json_response(409)

    %{"period" => %{"status" => "approved"}} =
      conn |> as(ctx.admin) |> post(path(ctx, "/periods/#{id}/approve")) |> json_response(200)

    assert %{"code" => "coach_pay_period_locked"} =
             conn
             |> as(ctx.admin)
             |> post(path(ctx, "/periods/#{id}/calculate"))
             |> json_response(409)

    assert %{"statements" => [%{"total_cents" => 2_400, "lines" => lines}]} =
             conn |> as(ctx.coach) |> get(path(ctx, "/mine")) |> json_response(200)

    assert length(lines) == 3

    export = conn |> as(ctx.admin) |> get(path(ctx, "/periods/#{id}/export"))
    assert response(export, 200) =~ "24.00"
    assert [content_type | _] = get_resp_header(export, "content-type")
    assert content_type =~ "text/csv"

    %{"period" => %{"status" => "exported"}} =
      conn |> as(ctx.admin) |> get(path(ctx, "/periods/#{id}")) |> json_response(200)

    assert %{"code" => "coach_pay_period_exported"} =
             conn
             |> as(ctx.admin)
             |> post(path(ctx, "/periods/#{id}/reopen"), %{reason: "Λάθος"})
             |> json_response(409)
  end

  defp tenant_fixture(user, name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    add_tenant_member(organization, user, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    {organization, context}
  end

  defp add_tenant_member(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end
end
