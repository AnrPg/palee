defmodule Palee.CoachPay.Domain.CoachPayPlusTest do
  @moduledoc "ADR-382: fixed pay, new sales scopes, overtime, lines by hand, gross/net, PDF."
  use ExUnit.Case, async: true

  alias Palee.CoachPay.Domain.{
    AmountBasis,
    PayCalculator,
    PayItemPolicy,
    Payslip,
    PeriodPolicy,
    Proration,
    RulePolicy,
    StatementGroups
  }

  @coach "00000000-0000-0000-0000-0000000000c1"
  @other "00000000-0000-0000-0000-0000000000c2"
  @member "00000000-0000-0000-0000-0000000000d1"
  @stranger "00000000-0000-0000-0000-0000000000d2"

  defp rule(kind, attrs) do
    {:ok, rule} =
      RulePolicy.change(
        %{},
        Map.merge(
          %{
            "kind" => kind,
            "coach_user_id" => @coach,
            "currency" => "EUR",
            "starts_on" => "2027-01-01"
          },
          attrs
        )
      )

    Map.put(rule, :id, Ecto.UUID.generate())
  end

  defp item(attrs) do
    {:ok, item} =
      PayItemPolicy.change(
        %{},
        Map.merge(
          %{
            "kind" => "overtime",
            "name" => "Υπερωρία",
            "amount_cents" => 1_200,
            "unit" => "per_hour",
            "roles" => ["coach"],
            "weekly_threshold" => 2,
            "currency" => "EUR"
          },
          attrs
        )
      )

    item |> Map.put(:id, Ecto.UUID.generate()) |> Map.put(:archived_at, nil)
  end

  defp period(from, to), do: %{period: %{starts_on: from, ends_on: to}}

  describe "rounding and proration" do
    test "amounts round half away from zero, once per line" do
      assert Proration.amount(100, 1, 3) == 33
      assert Proration.amount(100, 2, 3) == 67
      assert Proration.amount(150, 1, 60) == 3
      assert Proration.amount(30, 1, 60) == 1
      assert Proration.amount(29, 1, 60) == 0
      assert Proration.amount(-100, 2, 3) == -67
      assert Proration.amount(100_000, 31, 31) == 100_000
    end

    test "monthly: a full month pays exactly, a part month its days of that month" do
      rule = rule("fixed", %{"amount_cents" => 120_000, "frequency" => "monthly"})

      lines =
        [rule]
        |> PayCalculator.calculate(period(~D[2027-01-01], ~D[2027-01-31]), "EUR")
        |> Map.fetch!(@coach)

      assert [%{kind: "fixed", quantity: 31, quantity_divisor: 31, amount_cents: 120_000}] =
               lines

      # Valid from the 15th of February (28 days): 14/28 of the month.
      rule = %{rule | starts_on: ~D[2027-02-15]}

      assert %{@coach => [%{quantity: 14, quantity_divisor: 28, amount_cents: 60_000}]} =
               PayCalculator.calculate(
                 [rule],
                 period(~D[2027-02-01], ~D[2027-02-28]),
                 "EUR"
               )
    end

    test "monthly over two calendar months: one line per month" do
      rule = rule("fixed", %{"amount_cents" => 3_100, "frequency" => "monthly"})

      %{@coach => lines} =
        PayCalculator.calculate([rule], period(~D[2027-01-17], ~D[2027-02-14]), "EUR")

      assert [
               %{
                 occurred_on: ~D[2027-01-17],
                 quantity: 15,
                 quantity_divisor: 31,
                 amount_cents: 1_500
               },
               %{
                 occurred_on: ~D[2027-02-01],
                 quantity: 14,
                 quantity_divisor: 28,
                 amount_cents: 1_550
               }
             ] = lines
    end

    test "weekly and daily, and a rule that ends inside the period" do
      weekly = rule("fixed", %{"amount_cents" => 700, "frequency" => "weekly"})

      daily =
        rule("fixed", %{
          "amount_cents" => 1_000,
          "frequency" => "daily",
          "ends_on" => "2027-03-05"
        })

      %{@coach => lines} =
        PayCalculator.calculate([weekly, daily], period(~D[2027-03-01], ~D[2027-03-10]), "EUR")

      assert Enum.find(lines, &(&1.rule_id == weekly.id)).amount_cents == 1_000
      assert %{quantity: 5, amount_cents: 5_000} = Enum.find(lines, &(&1.rule_id == daily.id))
    end

    test "a fixed rule needs a frequency" do
      assert {:error, {:invalid_fields, %{"frequency" => "invalid"}}} =
               RulePolicy.change(%{}, %{
                 "kind" => "fixed",
                 "coach_user_id" => @coach,
                 "currency" => "EUR",
                 "starts_on" => "2027-01-01",
                 "amount_cents" => 100
               })
    end
  end

  describe "percent of subscriptions" do
    defp sale(attrs),
      do:
        Map.merge(
          %{
            kind: "payment",
            id: Ecto.UUID.generate(),
            occurred_on: ~D[2027-01-10],
            paid_on: ~D[2027-01-10],
            amount_cents: 10_000,
            currency: "EUR",
            package_name: "Unlimited",
            pt_coach_id: nil,
            sold_by_id: nil,
            member_user_id: @member,
            revenue_stream: "membership"
          },
          attrs
        )

    test "own clients: payments of the clients they coach on the day paid, refunds follow" do
      rule = rule("percent_of_sales", %{"percent_bps" => 1_000, "sales_scope" => "own_clients"})

      work = %{
        sales: [
          sale(%{}),
          sale(%{member_user_id: @stranger}),
          sale(%{member_user_id: @stranger, pt_coach_id: @coach, revenue_stream: "package"}),
          sale(%{revenue_stream: "shop"}),
          sale(%{occurred_on: ~D[2027-01-25], paid_on: ~D[2027-01-25]}),
          sale(%{kind: "reversal", amount_cents: -5_000, occurred_on: ~D[2027-01-28]})
        ],
        coach_clients: [
          %{
            coach_user_id: @coach,
            client_user_id: @member,
            from: ~D[2027-01-01],
            to: ~D[2027-01-20]
          }
        ]
      }

      %{@coach => lines} = PayCalculator.calculate([rule], work, "EUR")

      assert lines |> Enum.map(&{&1.kind, &1.amount_cents}) |> Enum.sort() ==
               [{"clawback", -500}, {"percent_of_sales", 1_000}, {"percent_of_sales", 1_000}]
    end

    test "a payment both personal_training and own_clients count is paid once, by personal_training" do
      personal =
        rule("percent_of_sales", %{"percent_bps" => 2_000, "sales_scope" => "personal_training"})

      own = rule("percent_of_sales", %{"percent_bps" => 1_000, "sales_scope" => "own_clients"})
      both = sale(%{pt_coach_id: @coach})
      only_own = sale(%{})

      work = %{
        sales: [both, only_own],
        coach_clients: [
          %{coach_user_id: @coach, client_user_id: @member, from: ~D[2027-01-01], to: nil}
        ]
      }

      %{@coach => lines} = PayCalculator.calculate([own, personal], work, "EUR")

      assert lines |> Enum.map(&{&1.source_id, &1.rule_id, &1.amount_cents}) |> Enum.sort() ==
               Enum.sort([{both.id, personal.id, 2_000}, {only_own.id, own.id, 1_000}])
    end

    test "box_all: every subscription and package payment, no shop" do
      rule = rule("percent_of_sales", %{"percent_bps" => 250, "sales_scope" => "box_all"})

      work = %{
        sales: [
          sale(%{member_user_id: @stranger}),
          sale(%{revenue_stream: "package"}),
          sale(%{revenue_stream: "shop"}),
          sale(%{revenue_stream: "event"})
        ]
      }

      %{@coach => lines} = PayCalculator.calculate([rule], work, "EUR")
      assert Enum.map(lines, & &1.amount_cents) == [250, 250]
    end
  end

  describe "combined rules" do
    test "any number of rules of any kinds pay together, one group each" do
      fixed = rule("fixed", %{"amount_cents" => 3_100, "frequency" => "monthly"})
      per_class = rule("per_class", %{"amount_cents" => 1_500})
      percent = rule("percent_of_sales", %{"percent_bps" => 1_000, "sales_scope" => "box_all"})

      work =
        period(~D[2027-01-01], ~D[2027-01-31])
        |> Map.merge(%{
          classes:
            for day <- [4, 5] do
              %{
                class_id: Ecto.UUID.generate(),
                coach_user_id: @coach,
                class_type_id: nil,
                name: "WOD",
                occurred_on: Date.new!(2027, 1, day),
                duration_minutes: 60,
                attendance: %{"attended" => 5}
              }
            end,
          sales: [
            %{
              kind: "payment",
              id: Ecto.UUID.generate(),
              occurred_on: ~D[2027-01-10],
              amount_cents: 5_000,
              currency: "EUR",
              package_name: "Unlimited",
              pt_coach_id: nil,
              sold_by_id: nil,
              member_user_id: @member,
              revenue_stream: "membership"
            }
          ]
        })

      rules = [fixed, per_class, percent]
      %{@coach => lines} = by_coach = PayCalculator.calculate(rules, work, "EUR")
      terms = PayCalculator.terms_by_coach(rules, [], by_coach)

      groups = StatementGroups.groups(%{lines: lines, rule_terms: terms[@coach]})

      assert Enum.map(groups, &{&1.kind, &1.quantity, &1.unit_cents, &1.amount_cents}) == [
               {"fixed", 31, 3_100, 3_100},
               {"per_class", 2, 1_500, 3_000},
               {"percent_of_sales", 1, nil, 500}
             ]

      assert hd(groups).terms["frequency"] == "monthly"
      assert PayCalculator.total(lines) == 6_600
    end
  end

  describe "overtime" do
    defp led(user, day, minutes),
      do: %{
        class_id: Ecto.UUID.generate(),
        coach_user_id: user,
        class_type_id: nil,
        name: "WOD",
        occurred_on: day,
        duration_minutes: minutes,
        attendance: %{}
      }

    test "hours above the weekly threshold (Monday to Sunday), for the item's roles" do
      overtime = item(%{})

      classes = [
        # Week of Monday 4 January 2027: 3 hours, threshold 2 → 60 minutes.
        led(@coach, ~D[2027-01-04], 60),
        led(@coach, ~D[2027-01-06], 60),
        led(@coach, ~D[2027-01-10], 60),
        # Week of 11 January: 2 hours, none above.
        led(@coach, ~D[2027-01-11], 120),
        # Not a coach: no overtime.
        led(@other, ~D[2027-01-04], 600)
      ]

      work =
        period(~D[2027-01-04], ~D[2027-01-17])
        |> Map.merge(%{
          classes: classes,
          pay_items: [overtime],
          staff_roles: %{@coach => ["coach"], @other => ["front_desk"]}
        })

      assert %{@coach => [line]} = PayCalculator.calculate([], work, "EUR")

      assert %{
               kind: "overtime",
               quantity: 60,
               quantity_divisor: 60,
               unit_cents: 1_200,
               amount_cents: 1_200,
               occurred_on: ~D[2027-01-04],
               source_type: "pay_item"
             } = line
    end

    test "a week the period cuts gets a prorated threshold" do
      # Period starts Friday 8 January: 3 days of that week, threshold 7 h → 3 h.
      overtime = item(%{"weekly_threshold" => 7})

      work =
        period(~D[2027-01-08], ~D[2027-01-31])
        |> Map.merge(%{
          classes: [led(@coach, ~D[2027-01-08], 240)],
          pay_items: [overtime],
          staff_roles: %{@coach => ["coach", "head_coach"]}
        })

      assert %{@coach => [%{quantity: 60}]} = PayCalculator.calculate([], work, "EUR")
    end

    test "overtime is per hour with a required threshold; allowances have none" do
      assert {:error, {:invalid_fields, %{"weekly_threshold" => "invalid"}}} =
               PayItemPolicy.change(%{}, %{
                 "kind" => "overtime",
                 "name" => "OT",
                 "amount_cents" => 100,
                 "unit" => "per_hour",
                 "roles" => ["coach"],
                 "currency" => "EUR"
               })

      assert {:error, {:invalid_fields, %{"unit" => "invalid"}}} =
               PayItemPolicy.change(%{}, %{
                 "kind" => "overtime",
                 "name" => "OT",
                 "amount_cents" => 100,
                 "unit" => "per_extra_class",
                 "roles" => ["coach"],
                 "weekly_threshold" => 5,
                 "currency" => "EUR"
               })

      assert {:error, {:invalid_fields, %{"weekly_threshold" => "invalid"}}} =
               PayItemPolicy.change(%{}, %{
                 "kind" => "allowance",
                 "name" => "Μετακίνηση",
                 "amount_cents" => 100,
                 "unit" => "per_period",
                 "roles" => ["front_desk"],
                 "weekly_threshold" => 5,
                 "currency" => "EUR"
               })

      assert {:error, {:invalid_fields, %{"roles" => "invalid"}}} =
               PayItemPolicy.change(%{}, %{
                 "kind" => "allowance",
                 "name" => "Μετακίνηση",
                 "amount_cents" => 100,
                 "unit" => "per_period",
                 "roles" => ["member"],
                 "currency" => "EUR"
               })
    end

    test "head coach is a coach whose scope is every client" do
      assert PayItemPolicy.person_roles([:coach], :all) == ["head_coach", "coach"]
      assert PayItemPolicy.person_roles([:coach], :own) == ["coach"]
      assert PayItemPolicy.person_roles([:member], :own) == []
    end
  end

  describe "lines by hand" do
    test "an allowance from the catalogue: occurrences, its basis, overtime refused" do
      allowance =
        item(%{
          "kind" => "allowance",
          "name" => "Μετακίνηση",
          "amount_cents" => 500,
          "unit" => "per_occurrence",
          "roles" => ["front_desk"],
          "weekly_threshold" => nil,
          "amount_basis" => "net"
        })

      assert {:ok,
              %{
                kind: "allowance",
                quantity: 3,
                amount_cents: 1_500,
                amount_basis: "net",
                note: "3 εκδρομές"
              }} =
               PayItemPolicy.manual_line(
                 allowance,
                 %{"quantity" => 3, "note" => " 3 εκδρομές "},
                 ~D[2027-01-31],
                 @coach
               )

      assert {:error, {:invalid_fields, %{"pay_item_id" => "counted_from_classes"}}} =
               PayItemPolicy.manual_line(item(%{}), %{}, ~D[2027-01-31], @coach)

      assert {:error, :coach_pay_item_archived} =
               PayItemPolicy.manual_line(
                 %{allowance | archived_at: DateTime.utc_now()},
                 %{},
                 ~D[2027-01-31],
                 @coach
               )
    end

    test "ad hoc payments and reimbursements: positive with a required note, audited" do
      assert {:ok,
              %{
                kind: "ad_hoc",
                note: "Κάλυψη Σαββάτου",
                created_by_id: @other,
                amount_basis: "gross"
              }} =
               PeriodPolicy.adjustment(
                 %{"kind" => "ad_hoc", "amount_cents" => 4_000, "note" => "Κάλυψη Σαββάτου"},
                 ~D[2027-01-31],
                 @other
               )

      assert {:error, {:invalid_fields, %{"note" => "required"}}} =
               PeriodPolicy.adjustment(
                 %{"kind" => "ad_hoc", "amount_cents" => 4_000},
                 ~D[2027-01-31],
                 @other
               )

      assert {:error, {:invalid_fields, %{"amount_cents" => "invalid"}}} =
               PeriodPolicy.adjustment(
                 %{"kind" => "ad_hoc", "amount_cents" => -4_000, "note" => "x"},
                 ~D[2027-01-31],
                 @other
               )

      assert {:ok, %{kind: "non_taxable_reimbursement", amount_basis: "net"}} =
               PeriodPolicy.adjustment(
                 %{
                   "kind" => "non_taxable_reimbursement",
                   "amount_cents" => 2_000,
                   "note" => "Βενζίνη",
                   "amount_basis" => "net"
                 },
                 ~D[2027-01-31],
                 @other
               )

      assert {:ok, %{amount_basis: "net"}} =
               PeriodPolicy.adjustment(
                 %{"kind" => "non_taxable_reimbursement", "amount_cents" => 2_000, "note" => "x"},
                 ~D[2027-01-31],
                 @other
               )

      assert {:ok, %{amount_basis: "gross"}} =
               PeriodPolicy.adjustment(
                 %{"kind" => "ad_hoc", "amount_cents" => 2_000, "note" => "x"},
                 ~D[2027-01-31],
                 @other
               )

      assert {:error, {:invalid_fields, %{"note" => "required"}}} =
               PeriodPolicy.adjustment(
                 %{"kind" => "non_taxable_reimbursement", "amount_cents" => 2_000},
                 ~D[2027-01-31],
                 @other
               )

      assert {:error, {:invalid_fields, %{"amount_basis" => "invalid"}}} =
               PeriodPolicy.adjustment(
                 %{"amount_cents" => 100, "description" => "x", "amount_basis" => "after_tax"},
                 ~D[2027-01-31],
                 @other
               )
    end
  end

  describe "gross and net" do
    test "rules pass their basis to their lines; groups and subtotals keep them apart" do
      net_rule = rule("per_class", %{"amount_cents" => 1_000, "amount_basis" => "net"})
      gross_rule = rule("fixed", %{"amount_cents" => 3_100, "frequency" => "monthly"})

      work =
        period(~D[2027-01-01], ~D[2027-01-31])
        |> Map.put(:classes, [led(@coach, ~D[2027-01-05], 60)])

      %{@coach => lines} = PayCalculator.calculate([net_rule, gross_rule], work, "EUR")
      assert AmountBasis.subtotals(lines) == %{gross_cents: 3_100, net_cents: 1_000}

      groups = StatementGroups.groups(%{lines: lines})

      assert Enum.map(groups, &{&1.kind, &1.amount_basis}) == [
               {"fixed", "gross"},
               {"per_class", "net"}
             ]

      # One rule's lines with different bases are never summed together.
      [line] = Enum.filter(lines, &(&1.kind == "per_class"))
      mixed = [line, %{line | amount_basis: "gross"}]
      assert length(StatementGroups.groups(%{lines: mixed})) == 2
      assert AmountBasis.deviates?(line)
    end
  end

  describe "basis kept on recalculation" do
    test "a calculated line takes the basis staff chose on the line it replaces" do
      line = %{
        rule_id: "r1",
        pay_item_id: nil,
        kind: "per_class",
        source_type: "class",
        source_id: "c1",
        occurred_on: ~D[2027-01-04],
        amount_basis: "gross"
      }

      other = %{line | source_id: "c2"}

      previous = [
        %{line | amount_basis: "net"},
        %{other | source_id: "gone", amount_basis: "net"}
      ]

      assert [%{amount_basis: "net"}, %{amount_basis: "gross"}] =
               AmountBasis.keep_choices([line, other], previous)
    end
  end

  describe "pay statement PDF" do
    defp labels(language) do
      Map.new(Payslip.label_messages(), fn {key, message} ->
        {key, Palee.Localization.translate(language, message, %{}, "coach_pay")}
      end)
    end

    defp view(language) do
      fixed_terms = %{
        "source" => "rule",
        "kind" => "fixed",
        "amount_cents" => 120_000,
        "frequency" => "monthly"
      }

      %{
        business: %{
          name: "CrossFit Θέρμη",
          lines: ["Εγνατίας 1", "54636 Θεσσαλονίκη"],
          ids: [{"TIN", "123456789"}]
        },
        person: "Μαρία",
        period: %{
          starts_on: ~D[2027-01-01],
          ends_on: ~D[2027-01-31],
          approved_at: ~U[2027-02-01 10:00:00Z]
        },
        currency: "EUR",
        gross_cents: 120_000,
        net_cents: 6_000,
        language: language,
        groups: [
          %{
            key: "rule:r1:gross",
            kind: "fixed",
            rule_id: "r1",
            pay_item_id: nil,
            amount_basis: "gross",
            terms: fixed_terms,
            line_count: 1,
            quantity: 31,
            quantity_divisor: 31,
            unit_cents: 120_000,
            base_cents: nil,
            amount_cents: 120_000
          }
        ],
        manual: [
          %{
            kind: "ad_hoc",
            description: "Κάλυψη Σαββάτου",
            note: "Κάλυψη Σαββάτου",
            amount_cents: 4_000,
            amount_basis: "net"
          },
          %{
            kind: "non_taxable_reimbursement",
            description: "Βενζίνη",
            note: "Βενζίνη για αγώνες",
            amount_cents: 2_000,
            amount_basis: "net"
          }
        ]
      }
    end

    test "Greek: the internal label, groups, notes, the net marker and both subtotals" do
      texts = Payslip.texts(view("el"), labels("el"), Palee.Pdf.Fonts.sans())
      joined = Enum.join(texts, "\n")

      assert "Εκκαθαριστικό" in texts
      assert "Εσωτερική κατάσταση αμοιβής" in texts
      assert joined =~ "δεν είναι επίσημο έγγραφο μισθοδοσίας"
      assert "Σταθερός μισθός" in texts
      assert "1.200,00 EUR ανά μήνα" in texts
      assert "31/31 × 1.200,00 EUR" in texts
      assert "Έκτακτη πληρωμή · Κάλυψη Σαββάτου" in texts
      assert joined =~ "Σημείωση: Βενζίνη για αγώνες"
      assert Enum.count(texts, &(&1 == "Καθαρά")) == 2
      assert "Μικτά 1.200,00 EUR · Καθαρά 60,00 EUR" in texts
      assert "CrossFit Θέρμη" in texts
    end

    test "English labels and the PDF bytes" do
      texts = Payslip.texts(view("en"), labels("en"), Palee.Pdf.Fonts.sans())
      assert "Internal pay statement" in texts
      assert "Gross 1,200.00 EUR · Net 60.00 EUR" in texts

      pdf = Payslip.render(view("en"), labels("en"), Palee.Pdf.Fonts.sans())
      assert "%PDF-" <> _rest = pdf
    end
  end
end
