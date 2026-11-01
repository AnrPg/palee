defmodule Palee.CoachPay.CoachPayPlusRLSTest do
  @moduledoc """
  ADR-382 under real row-level security (the non-superuser runtime role):
  the box's catalogue of overtime and allowances stays in its box, a period
  is calculated with fixed pay and overtime, an allowance and a payment by
  hand are added, a line is marked net, and the totals keep gross and net
  apart.
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.CoachPay.CoachPayService
  alias Palee.{CoachPay, Organizations, RLSCase}
  alias Palee.Scheduling.ScheduledClass

  defp tenant(owner, name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    member(organization, owner, :owner)
    organization
  end

  defp member(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end

  defp context(user, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end

  test "pay items, fixed pay, overtime and lines by hand under RLS" do
    RLSCase.ensure_runtime_role!()

    owner = admin_fixture(%{nickname: "rlspay_owner"})
    coach = user_fixture(%{role: :member, nickname: "rlspay_coach"})
    desk = user_fixture(%{role: :member, nickname: "rlspay_desk"})
    box = tenant(owner, "RLS Pay Box")
    member(box, coach, :coach)
    member(box, desk, :front_desk)

    other_owner = admin_fixture(%{nickname: "rlspay_other"})
    neighbour = tenant(other_owner, "RLS Pay Neighbour")

    owner_ctx = context(owner, box)
    workout = workout_fixture(owner, %{tenant_context: owner_ctx})
    class_type = class_type_fixture(%{tenant_context: owner_ctx, name: "WOD"})

    # A 90-minute class the coach led two days ago (written as the owner role).
    Repo.insert!(%ScheduledClass{
      organization_id: box.id,
      master_workout_id: workout.id,
      class_type_id: class_type.id,
      coach_user_id: coach.id,
      scheduled_at: DateTime.add(DateTime.utc_now(), -2, :day) |> DateTime.truncate(:second),
      duration_minutes: 90,
      capacity: 10
    })

    Repo.query!("SET LOCAL ROLE #{RLSCase.runtime_role()}")
    ctx = context(owner, box)
    other_ctx = context(other_owner, neighbour)

    {:ok, overtime} =
      CoachPayService.create_item(ctx, %{
        "kind" => "overtime",
        "name" => "Υπερωρία",
        "amount_cents" => 2_000,
        "unit" => "per_hour",
        "roles" => ["coach"],
        "weekly_threshold" => 0
      })

    {:ok, allowance} =
      CoachPayService.create_item(ctx, %{
        "kind" => "allowance",
        "name" => "Επίδομα μετακίνησης",
        "amount_cents" => 1_500,
        "unit" => "per_period",
        "roles" => ["front_desk"],
        "amount_basis" => "net"
      })

    assert overtime.currency == "EUR"

    # The neighbour box sees none of it.
    assert %{items: []} = CoachPayService.items(other_ctx, %{})
    assert {:error, :not_found} = CoachPay.update_item(other_ctx, overtime.id, %{"name" => "x"})
    assert %{items: [_one, _two]} = CoachPayService.items(ctx, %{})

    today = Date.utc_today()

    {:ok, _rule} =
      CoachPayService.create_rule(ctx, %{
        "coach_user_id" => coach.id,
        "kind" => "fixed",
        "amount_cents" => 1_000,
        "frequency" => "daily",
        "starts_on" => Date.add(today, -60)
      })

    {:ok, period} =
      CoachPayService.create_period(ctx, %{
        starts_on: Date.add(today, -9),
        ends_on: Date.add(today, 2)
      })

    {:ok, period} = CoachPayService.calculate(ctx, period.id)

    [statement] = period.statements
    assert statement.coach_user_id == coach.id
    # 12 days × 10,00 plus 1,5 h × 20,00.
    assert statement.gross_cents == 15_000
    assert statement.net_cents == 0
    assert Enum.map(statement.groups, & &1.kind) == ["fixed", "overtime"]

    # The allowance goes to the front desk only; the coach does not hold its role.
    assert {:error, {:invalid_fields, %{"user_id" => "role_not_covered"}}} =
             CoachPayService.add_pay_item_line(ctx, period.id, %{
               "pay_item_id" => allowance.id,
               "user_id" => coach.id
             })

    {:ok, period} =
      CoachPayService.add_pay_item_line(ctx, period.id, %{
        "pay_item_id" => allowance.id,
        "user_id" => desk.id,
        "note" => "Νοέμβριος"
      })

    {:ok, period} =
      CoachPayService.add_adjustment(ctx, period.id, %{
        coach_user_id: coach.id,
        kind: "ad_hoc",
        amount_cents: 4_000,
        note: "Κάλυψη Σαββάτου"
      })

    desk_statement = Enum.find(period.statements, &(&1.coach_user_id == desk.id))
    assert %{net_cents: 1_500, gross_cents: 0, net_line_count: 1} = desk_statement
    assert [%{deviates_from_default: true, note: "Νοέμβριος"}] = desk_statement.lines

    coach_statement = Enum.find(period.statements, &(&1.coach_user_id == coach.id))
    ad_hoc = Enum.find(coach_statement.lines, &(&1.kind == "ad_hoc"))
    assert ad_hoc.created_by_id == owner.id
    assert ad_hoc.inserted_at

    # Mark the payment by hand net; recalculating keeps it and its basis.
    {:ok, _period} =
      CoachPayService.set_line_basis(ctx, period.id, ad_hoc.id, %{"amount_basis" => "net"})

    {:ok, period} = CoachPayService.calculate(ctx, period.id)
    coach_statement = Enum.find(period.statements, &(&1.coach_user_id == coach.id))
    assert %{gross_cents: 15_000, net_cents: 4_000, net_line_count: 1} = coach_statement
    assert %{gross_cents: 15_000, net_cents: 5_500} = period

    # The neighbour cannot reach the period or its lines.
    assert {:error, :not_found} = CoachPay.get_period(other_ctx, period.id)

    assert {:error, :not_found} =
             CoachPay.set_line_basis(other_ctx, period.id, ad_hoc.id, "gross")

    {:ok, _approved} = CoachPayService.approve(ctx, period.id)

    assert {:ok, %{content: "%PDF-" <> _pdf, content_type: "application/pdf"}} =
             CoachPayService.payslip(ctx, period.id, coach.id, "el")

    assert {:ok, %{periods: [%{statements: [_one, _two]}]}} = CoachPayService.summary(ctx, %{})
    assert {:ok, %{periods: []}} = CoachPayService.summary(other_ctx, %{})

    assert %{totals: [%{currency: "EUR", gross_cents: 15_000, net_cents: 4_000}]} =
             CoachPayService.person_statements(ctx, coach.id)
  end

  test "the catalogue is part of coach pay's retained tenant data" do
    tables = Enum.map(CoachPay.tenant_data_policy().tables, & &1.table)
    assert "coach_pay_items" in tables
  end
end
