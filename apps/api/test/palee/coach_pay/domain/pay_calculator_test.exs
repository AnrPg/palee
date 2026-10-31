defmodule Palee.CoachPay.Domain.PayCalculatorTest do
  use ExUnit.Case, async: true

  alias Palee.CoachPay.Domain.{PayCalculator, PeriodPolicy, RulePolicy, StatementExport}

  @coach "00000000-0000-0000-0000-0000000000c1"
  @other "00000000-0000-0000-0000-0000000000c2"
  @crossfit "00000000-0000-0000-0000-0000000000a1"
  @yoga "00000000-0000-0000-0000-0000000000a2"

  defp rule(kind, attrs) do
    {:ok, rule} =
      RulePolicy.change(
        %{},
        Map.merge(
          %{
            "kind" => kind,
            "coach_user_id" => @coach,
            "currency" => "EUR",
            "starts_on" => "2027-05-01"
          },
          attrs
        )
      )

    Map.put(rule, :id, Ecto.UUID.generate())
  end

  defp class(id, attrs) do
    Map.merge(
      %{
        class_id: id,
        coach_user_id: @coach,
        class_type_id: @crossfit,
        name: "CrossFit",
        occurred_on: ~D[2027-05-03],
        attendance: %{"attended" => 8, "late_cancel" => 1, "no_show" => 1}
      },
      attrs
    )
  end

  defp work(attrs), do: Map.merge(%{classes: [], sessions: [], sales: []}, attrs)

  test "per class: one line per class with enough people, of the chosen types" do
    rule = rule("per_class", %{"amount_cents" => 2_500, "class_type_ids" => [@crossfit], "min_attendees" => 3})

    work =
      work(%{
        classes: [
          class(Ecto.UUID.generate(), %{}),
          class(Ecto.UUID.generate(), %{attendance: %{"attended" => 2}}),
          class(Ecto.UUID.generate(), %{class_type_id: @yoga}),
          class(Ecto.UUID.generate(), %{coach_user_id: @other}),
          class(Ecto.UUID.generate(), %{occurred_on: ~D[2027-04-30]})
        ]
      })

    assert %{@coach => [line]} = PayCalculator.calculate([rule], work, "EUR")
    assert line.amount_cents == 2_500 and line.source_type == "scheduled_class"
    assert line.rule_id == rule.id
  end

  test "per attendee counts the chosen statuses, up to the cap" do
    rule =
      rule("per_attendee", %{
        "amount_cents" => 300,
        "count_statuses" => ["attended", "late_cancel"],
        "max_attendees" => 8
      })

    assert %{@coach => [line]} =
             PayCalculator.calculate([rule], work(%{classes: [class(Ecto.UUID.generate(), %{})]}), "EUR")

    assert line.quantity == 8 and line.amount_cents == 2_400
  end

  test "per session pays sessions someone attended" do
    rule = rule("per_session", %{"amount_cents" => 1_500})

    sessions = [
      %{slot_id: Ecto.UUID.generate(), coach_user_id: @coach, kind: "pt_session", occurred_on: ~D[2027-05-04], bookings: %{"attended" => 1}},
      %{slot_id: Ecto.UUID.generate(), coach_user_id: @coach, kind: "pt_session", occurred_on: ~D[2027-05-05], bookings: %{"no_show" => 1}}
    ]

    assert %{@coach => [%{amount_cents: 1_500, source_type: "appointment_slot"}]} =
             PayCalculator.calculate([rule], work(%{sessions: sessions}), "EUR")
  end

  test "a percent of attributed sales, with refunds taken back" do
    rule = rule("percent_of_sales", %{"percent_bps" => 1_000, "sales_scope" => "personal_training"})

    sales = [
      %{kind: "payment", id: Ecto.UUID.generate(), occurred_on: ~D[2027-05-06], amount_cents: 20_000, currency: "EUR", package_name: "PT 10", pt_coach_id: @coach, sold_by_id: nil},
      %{kind: "reversal", id: Ecto.UUID.generate(), occurred_on: ~D[2027-05-07], amount_cents: -5_005, currency: "EUR", package_name: "PT 10", pt_coach_id: @coach, sold_by_id: nil},
      %{kind: "payment", id: Ecto.UUID.generate(), occurred_on: ~D[2027-05-06], amount_cents: 9_000, currency: "EUR", package_name: "Monthly", pt_coach_id: nil, sold_by_id: @coach},
      %{kind: "payment", id: Ecto.UUID.generate(), occurred_on: ~D[2027-05-06], amount_cents: 9_000, currency: "USD", package_name: "PT", pt_coach_id: @coach, sold_by_id: nil}
    ]

    assert %{@coach => [sale, clawback]} = PayCalculator.calculate([rule], work(%{sales: sales}), "EUR")
    assert sale.kind == "percent_of_sales" and sale.amount_cents == 2_000 and sale.base_cents == 20_000
    assert clawback.kind == "clawback" and clawback.amount_cents == -501
    assert clawback.source_type == "finance_reversal"
    assert PayCalculator.total([sale, clawback]) == 1_499
  end

  test "a rule in another currency, or outside its dates, pays nothing" do
    rule = rule("per_class", %{"amount_cents" => 100, "currency" => "usd"})
    assert PayCalculator.calculate([rule], work(%{classes: [class(Ecto.UUID.generate(), %{})]}), "EUR") == %{}

    dated = rule("per_class", %{"amount_cents" => 100, "starts_on" => "2027-05-04"})
    assert PayCalculator.calculate([dated], work(%{classes: [class(Ecto.UUID.generate(), %{})]}), "EUR") == %{}
  end

  test "rules are checked field by field" do
    assert {:error, {:invalid_fields, errors}} =
             RulePolicy.change(%{}, %{"kind" => "percent_of_sales", "coach_user_id" => "x", "currency" => "EUR", "starts_on" => "2027-05-01"})

    assert errors == %{"coach_user_id" => "required", "percent_bps" => "invalid", "sales_scope" => "invalid"}

    assert {:error, {:invalid_fields, %{"ends_on" => "invalid"}}} =
             RulePolicy.change(%{}, %{"kind" => "per_class", "amount_cents" => 1, "coach_user_id" => @coach, "currency" => "EUR", "starts_on" => "2027-05-01", "ends_on" => "2027-04-01"})
  end

  test "archiving ends a rule today, or at its start when it has not begun" do
    rule = rule("per_class", %{"amount_cents" => 1})
    assert RulePolicy.archive(rule, ~D[2027-06-01]) == %{ends_on: ~D[2027-06-01]}
    assert RulePolicy.archive(rule, ~D[2027-04-01]) == %{ends_on: ~D[2027-05-01]}
  end

  test "a period's life" do
    now = ~U[2027-06-01 10:00:00Z]
    existing = [%{starts_on: ~D[2027-05-01], ends_on: ~D[2027-05-31]}]

    assert {:error, :coach_pay_period_overlaps} =
             PeriodPolicy.validate_new(~D[2027-05-31], ~D[2027-06-30], existing)

    assert :ok = PeriodPolicy.validate_new(~D[2027-06-01], ~D[2027-06-30], existing)

    assert {:error, {:invalid_fields, %{"ends_on" => "too_long"}}} =
             PeriodPolicy.validate_new(~D[2027-06-01], ~D[2027-12-31], [])

    assert {:ok, %{status: "approved"}} = PeriodPolicy.approve(%{status: "draft"}, @coach, now)
    assert {:error, :coach_pay_period_locked} = PeriodPolicy.editable?(%{status: "approved"})
    assert {:error, {:invalid_fields, _}} = PeriodPolicy.reopen(%{status: "approved"}, " ")
    assert {:ok, %{status: "draft", reopen_reason: "typo"}} = PeriodPolicy.reopen(%{status: "approved"}, "typo")
    assert {:error, :coach_pay_period_exported} = PeriodPolicy.reopen(%{status: "exported"}, "x")
    assert {:error, :coach_pay_period_not_approved} = PeriodPolicy.export(%{status: "draft"}, now)
    assert {:error, {:invalid_fields, _}} = PeriodPolicy.adjustment(%{"amount_cents" => 0, "description" => "x"}, ~D[2027-05-31], nil)
  end

  test "the CSV names every line and is safe in a spreadsheet" do
    period = %{starts_on: ~D[2027-05-01], ends_on: ~D[2027-05-31], currency: "EUR"}

    statements = [
      %{
        coach_user_id: @coach,
        lines: [
          %{occurred_on: ~D[2027-05-03], kind: "per_class", description: "=HYPERLINK(1)", quantity: 1, unit_cents: 2_500, base_cents: nil, percent_bps: nil, amount_cents: 2_500, source_type: "scheduled_class", source_id: @crossfit},
          %{occurred_on: ~D[2027-05-07], kind: "clawback", description: "PT, 10", quantity: 1, unit_cents: nil, base_cents: -5_005, percent_bps: 1_000, amount_cents: -501, source_type: "finance_reversal", source_id: nil}
        ]
      }
    ]

    csv = StatementExport.csv(period, statements, %{@coach => "Μαρία"})
    [header, first, second, ""] = String.split(csv, "\r\n")
    assert header =~ "period_start,period_end,coach"
    assert first =~ "Μαρία"
    assert first =~ "'=HYPERLINK(1)"
    assert first =~ ",25.00,EUR,"
    assert second =~ "\"PT, 10\""
    assert second =~ ",-50.05,10.00,-5.01,EUR,"
  end
end
