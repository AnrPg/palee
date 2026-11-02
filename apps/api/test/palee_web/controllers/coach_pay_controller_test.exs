defmodule PaleeWeb.CoachPayControllerTest do
  @moduledoc """
  ADR-341 (CP-A6) end to end under row-level security: pay rules, a period
  calculated from the classes a coach led, an adjustment, approval, the CSV
  export and the coach's own statement.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo}
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

  defp pay_path(ctx, rest), do: "/api/org/#{ctx.organization.slug}/admin/coach-pay#{rest}"
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
    |> post(
      pay_path(ctx, "/rules"),
      Map.merge(%{coach_user_id: ctx.coach.id, starts_on: start(-30)}, body)
    )
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
           |> post(pay_path(ctx, "/rules"), %{
             coach_user_id: outsider.id,
             kind: "per_class",
             amount_cents: 100,
             starts_on: start(-30)
           })
           |> json_response(422)

    %{"period" => %{"id" => id, "status" => "draft"}} =
      conn
      |> as(ctx.admin)
      |> post(pay_path(ctx, "/periods"), %{starts_on: start(-10), ends_on: start(1)})
      |> json_response(201)

    # Overlapping dates are refused.
    assert %{"code" => "coach_pay_period_overlaps"} =
             conn
             |> as(ctx.admin)
             |> post(pay_path(ctx, "/periods"), %{starts_on: start(-3), ends_on: start(3)})
             |> json_response(409)

    %{"period" => period} =
      conn
      |> as(ctx.admin)
      |> post(pay_path(ctx, "/periods/#{id}/calculate"))
      |> json_response(200)

    [statement] = period["statements"]
    assert statement["coach_user_id"] == ctx.coach.id
    # One class at 15,00 plus two attendees at 2,00 (the no-show does not count).
    assert statement["total_cents"] == 1_900
    assert Enum.sort(Enum.map(statement["lines"], & &1["kind"])) == ["per_attendee", "per_class"]

    %{"period" => period} =
      conn
      |> as(ctx.admin)
      |> post(pay_path(ctx, "/periods/#{id}/adjustments"), %{
        coach_user_id: ctx.coach.id,
        amount_cents: 500,
        description: "Κάλυψη τμήματος"
      })
      |> json_response(200)

    assert [%{"total_cents" => 2_400}] = period["statements"]

    # Calculating again keeps the adjustment.
    %{"period" => period} =
      conn
      |> as(ctx.admin)
      |> post(pay_path(ctx, "/periods/#{id}/calculate"))
      |> json_response(200)

    assert [%{"total_cents" => 2_400}] = period["statements"]

    # The coach sees nothing before approval, and cannot read the admin side.
    assert %{"statements" => []} =
             conn |> as(ctx.coach) |> get(pay_path(ctx, "/mine")) |> json_response(200)

    assert conn |> as(ctx.coach) |> get(pay_path(ctx, "/periods/#{id}")) |> response(403)

    assert %{"code" => "coach_pay_period_not_approved"} =
             conn
             |> as(ctx.admin)
             |> get(pay_path(ctx, "/periods/#{id}/export"))
             |> json_response(409)

    %{"period" => %{"status" => "approved"}} =
      conn |> as(ctx.admin) |> post(pay_path(ctx, "/periods/#{id}/approve")) |> json_response(200)

    assert %{"code" => "coach_pay_period_locked"} =
             conn
             |> as(ctx.admin)
             |> post(pay_path(ctx, "/periods/#{id}/calculate"))
             |> json_response(409)

    assert %{"statements" => [%{"total_cents" => 2_400, "lines" => lines}]} =
             conn |> as(ctx.coach) |> get(pay_path(ctx, "/mine")) |> json_response(200)

    assert length(lines) == 3

    export = conn |> as(ctx.admin) |> get(pay_path(ctx, "/periods/#{id}/export"))
    csv = response(export, 200)
    assert csv =~ ",per_class,Class,1,15.00,,,15.00,EUR,scheduled_class,"
    assert csv =~ ",adjustment,Κάλυψη τμήματος,1,,,,5.00,EUR,manual,"
    assert [content_type | _] = get_resp_header(export, "content-type")
    assert content_type =~ "text/csv"

    %{"period" => %{"status" => "exported"}} =
      conn |> as(ctx.admin) |> get(pay_path(ctx, "/periods/#{id}")) |> json_response(200)

    assert %{"code" => "coach_pay_period_exported"} =
             conn
             |> as(ctx.admin)
             |> post(pay_path(ctx, "/periods/#{id}/reopen"), %{reason: "Λάθος"})
             |> json_response(409)
  end

  describe "ADR-382" do
    setup ctx do
      desk = user_fixture(%{role: :member, nickname: "pay_desk"})
      add_tenant_member(ctx.organization, desk, :front_desk)
      %{desk: desk}
    end

    defp item(conn, ctx, body) do
      conn
      |> as(ctx.admin)
      |> post(pay_path(ctx, "/items"), body)
      |> json_response(201)
      |> Map.fetch!("item")
    end

    test "the catalogue of overtime and allowances is a setting, readable by Finance",
         %{conn: conn} = ctx do
      overtime =
        item(conn, ctx, %{
          kind: "overtime",
          name: "Υπερωρία",
          amount_cents: 2_000,
          unit: "per_hour",
          roles: ["coach", "head_coach"],
          weekly_threshold: 10
        })

      assert %{"currency" => "EUR", "amount_basis" => "gross", "roles" => ["head_coach", "coach"]} =
               overtime

      # Overtime needs its weekly threshold.
      assert %{"errors" => _errors} =
               conn
               |> as(ctx.admin)
               |> post(pay_path(ctx, "/items"), %{
                 kind: "overtime",
                 name: "Χωρίς όριο",
                 amount_cents: 2_000,
                 unit: "per_hour",
                 roles: ["coach"]
               })
               |> json_response(422)

      # A coach can neither change nor read the catalogue.
      assert conn
             |> as(ctx.coach)
             |> post(pay_path(ctx, "/items"), %{
               kind: "allowance",
               name: "x",
               amount_cents: 1,
               unit: "per_period",
               roles: ["coach"]
             })
             |> response(403)

      assert conn |> as(ctx.coach) |> get(pay_path(ctx, "/items")) |> response(403)

      %{"item" => %{"name" => "Υπερωρία 2"}} =
        conn
        |> as(ctx.admin)
        |> patch(pay_path(ctx, "/items/#{overtime["id"]}"), %{name: "Υπερωρία 2"})
        |> json_response(200)

      %{"item" => %{"archived_at" => archived}} =
        conn
        |> as(ctx.admin)
        |> post(pay_path(ctx, "/items/#{overtime["id"]}/archive"))
        |> json_response(200)

      assert archived

      assert %{"code" => "coach_pay_item_archived"} =
               conn
               |> as(ctx.admin)
               |> patch(pay_path(ctx, "/items/#{overtime["id"]}"), %{name: "x"})
               |> json_response(409)

      assert %{"items" => []} =
               conn |> as(ctx.admin) |> get(pay_path(ctx, "/items")) |> json_response(200)
    end

    test "fixed pay, lines by hand, gross and net, the PDF and the summaries",
         %{conn: conn} = ctx do
      led_class(ctx, ["attended"])

      rule(conn, ctx, %{kind: "per_class", amount_cents: 1_500, amount_basis: "net"})
      rule(conn, ctx, %{kind: "fixed", amount_cents: 1_000, frequency: "daily"})

      allowance =
        item(conn, ctx, %{
          kind: "allowance",
          name: "Επίδομα μετακίνησης",
          amount_cents: 2_500,
          unit: "per_occurrence",
          roles: ["front_desk"]
        })

      %{"period" => %{"id" => id}} =
        conn
        |> as(ctx.admin)
        |> post(pay_path(ctx, "/periods"), %{starts_on: start(-9), ends_on: start(2)})
        |> json_response(201)

      %{"period" => period} =
        conn
        |> as(ctx.admin)
        |> post(pay_path(ctx, "/periods/#{id}/calculate"))
        |> json_response(200)

      [statement] = period["statements"]
      # 12 days × 10,00 gross; one class at 15,00 net.
      assert %{"gross_cents" => 12_000, "net_cents" => 1_500, "net_line_count" => 1} = statement

      assert [
               %{"kind" => "fixed", "amount_basis" => "gross", "quantity" => 12},
               %{"kind" => "per_class", "amount_basis" => "net", "amount_cents" => 1_500}
             ] = statement["groups"]

      assert hd(statement["groups"])["terms"]["frequency"] == "daily"

      per_class = Enum.find(statement["lines"], &(&1["kind"] == "per_class"))
      assert per_class["deviates_from_default"] == true

      # A payment by hand needs its reason; a reimbursement too.
      assert conn
             |> as(ctx.admin)
             |> post(pay_path(ctx, "/periods/#{id}/adjustments"), %{
               coach_user_id: ctx.coach.id,
               kind: "ad_hoc",
               amount_cents: 3_000
             })
             |> json_response(422)

      %{"period" => _period} =
        conn
        |> as(ctx.admin)
        |> post(pay_path(ctx, "/periods/#{id}/adjustments"), %{
          coach_user_id: ctx.coach.id,
          kind: "ad_hoc",
          amount_cents: 3_000,
          note: "Κάλυψη Σαββάτου"
        })
        |> json_response(200)

      %{"period" => _period} =
        conn
        |> as(ctx.admin)
        |> post(pay_path(ctx, "/periods/#{id}/adjustments"), %{
          coach_user_id: ctx.coach.id,
          kind: "non_taxable_reimbursement",
          amount_cents: 2_000,
          note: "Βενζίνη για αγώνες"
        })
        |> json_response(200)

      %{"period" => period} =
        conn
        |> as(ctx.admin)
        |> post(pay_path(ctx, "/periods/#{id}/pay-items"), %{
          pay_item_id: allowance["id"],
          user_id: ctx.desk.id,
          quantity: 2
        })
        |> json_response(200)

      coach_statement = Enum.find(period["statements"], &(&1["coach_user_id"] == ctx.coach.id))
      ad_hoc = Enum.find(coach_statement["lines"], &(&1["kind"] == "ad_hoc"))
      assert ad_hoc["note"] == "Κάλυψη Σαββάτου"
      assert ad_hoc["created_by_id"] == ctx.admin.id

      # Staff mark the payment by hand net.
      %{"period" => period} =
        conn
        |> as(ctx.admin)
        |> patch(pay_path(ctx, "/periods/#{id}/lines/#{ad_hoc["id"]}"), %{amount_basis: "net"})
        |> json_response(200)

      coach_statement = Enum.find(period["statements"], &(&1["coach_user_id"] == ctx.coach.id))

      assert %{"gross_cents" => 12_000, "net_cents" => 6_500, "net_line_count" => 3} =
               coach_statement

      assert %{"gross_cents" => 17_000, "net_cents" => 6_500} = period

      # A basis staff chose on a calculated line survives a recalculation.
      fixed = Enum.find(coach_statement["lines"], &(&1["kind"] == "fixed"))

      conn
      |> as(ctx.admin)
      |> patch(pay_path(ctx, "/periods/#{id}/lines/#{fixed["id"]}"), %{amount_basis: "net"})
      |> json_response(200)

      %{"period" => period} =
        conn
        |> as(ctx.admin)
        |> post(pay_path(ctx, "/periods/#{id}/calculate"))
        |> json_response(200)

      coach_statement = Enum.find(period["statements"], &(&1["coach_user_id"] == ctx.coach.id))
      fixed = Enum.find(coach_statement["lines"], &(&1["kind"] == "fixed"))
      assert fixed["amount_basis"] == "net"
      assert %{"gross_cents" => 0, "net_cents" => 18_500} = coach_statement

      %{"period" => period} =
        conn
        |> as(ctx.admin)
        |> patch(pay_path(ctx, "/periods/#{id}/lines/#{fixed["id"]}"), %{amount_basis: "gross"})
        |> json_response(200)

      assert %{"gross_cents" => 17_000, "net_cents" => 6_500} = period

      %{"period" => %{"status" => "approved"}} =
        conn
        |> as(ctx.admin)
        |> post(pay_path(ctx, "/periods/#{id}/approve"))
        |> json_response(200)

      # The PDF: staff for anyone, the coach for their own.
      pdf =
        conn
        |> as(ctx.admin)
        |> get(pay_path(ctx, "/periods/#{id}/statements/#{ctx.coach.id}/pdf?language=en"))

      assert "%PDF-" <> _rest = response(pdf, 200)
      assert [content_type | _] = get_resp_header(pdf, "content-type")
      assert content_type =~ "application/pdf"

      assert %{"code" => "unsupported_language"} =
               conn
               |> as(ctx.admin)
               |> get(pay_path(ctx, "/periods/#{id}/statements/#{ctx.coach.id}/pdf?language=xx"))
               |> json_response(422)

      assert "%PDF-" <> _rest =
               conn |> as(ctx.coach) |> get(pay_path(ctx, "/mine/#{id}/pdf")) |> response(200)

      assert conn
             |> as(ctx.coach)
             |> get(pay_path(ctx, "/periods/#{id}/statements/#{ctx.desk.id}/pdf"))
             |> response(403)

      # The front desk reads their own allowance, with totals.
      assert %{
               "statements" => [%{"net_cents" => 0, "gross_cents" => 5_000}],
               "totals" => [
                 %{"currency" => "EUR", "gross_cents" => 5_000, "statement_count" => 1}
               ]
             } = conn |> as(ctx.desk) |> get(pay_path(ctx, "/mine")) |> json_response(200)

      # The coach's staff profile and Finance's summary.
      assert %{"totals" => [%{"gross_cents" => 12_000, "net_cents" => 6_500}]} =
               conn
               |> as(ctx.admin)
               |> get(pay_path(ctx, "/people/#{ctx.coach.id}/statements"))
               |> json_response(200)

      assert conn
             |> as(ctx.coach)
             |> get(pay_path(ctx, "/people/#{ctx.coach.id}/statements"))
             |> response(403)

      assert %{"periods" => [%{"id" => ^id, "statements" => statements}]} =
               conn |> as(ctx.admin) |> get(pay_path(ctx, "/summary")) |> json_response(200)

      assert Enum.map(statements, & &1["coach_name"]) |> Enum.sort() == ["pay_coach", "pay_desk"]

      assert %{"periods" => []} =
               conn
               |> as(ctx.admin)
               |> get(pay_path(ctx, "/summary?from=#{start(30)}"))
               |> json_response(200)

      # The CSV keeps every line with its basis.
      csv = conn |> as(ctx.admin) |> get(pay_path(ctx, "/periods/#{id}/export")) |> response(200)
      assert csv =~ ",non_taxable_reimbursement,Βενζίνη για αγώνες,"
      assert csv =~ ",net\r\n"
    end
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
