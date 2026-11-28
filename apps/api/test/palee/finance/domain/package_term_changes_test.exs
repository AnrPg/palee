defmodule Palee.Finance.Domain.PackageTermChangesTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.PackageTermChanges, as: Terms

  @visits "group_classes.visits"
  @window "booking.window_days"
  @cutoff "booking.cancellation_cutoff_hours"

  defp terms(price, fields, period \\ "monthly"),
    do: %{price_cents: price, billing_period: period, fields: fields}

  defp holder(overrides \\ %{}, membership \\ %{}) do
    subscription =
      Map.merge(
        %{
          price_cents_snapshot: 6000,
          billing_period_snapshot: "monthly",
          params_snapshot: %{
            "entitlement_version" => 2,
            "package_type" => "membership",
            "fields" => %{@visits => %{"limit" => 12, "period" => "calendar_month"}, @window => 7}
          },
          starts_on: ~D[2026-11-05],
          ends_on: nil,
          auto_renew: true,
          status: "active"
        },
        overrides
      )

    %{
      subscription: subscription,
      membership: Map.merge(%{left_at: nil, leaving_on: nil}, membership)
    }
  end

  defp own_fields(holder),
    do: Terms.package_terms(6000, "monthly", holder.subscription.params_snapshot).fields

  describe "direction/3" do
    test "more visits, unlimited, a wider scope and a later cutoff are better" do
      assert Terms.direction(@visits, %{"limit" => 8, "period" => "calendar_month"}, %{
               "limit" => 12,
               "period" => "calendar_month"
             }) == :better

      assert Terms.direction(@visits, %{"limit" => 8, "period" => "calendar_month"}, %{
               "limit" => "unlimited",
               "period" => "calendar_month"
             }) == :better

      assert Terms.direction("group_classes.class_types", ["a"], ["a", "b"]) == :better
      assert Terms.direction("group_classes.class_types", ["a", "b"], "all") == :better
      assert Terms.direction(@cutoff, 12, 2) == :better
      assert Terms.direction("booking.daily_limit", 2, nil) == :better

      assert Terms.direction("terms.validity", %{"amount" => 1, "unit" => "month"}, %{
               "amount" => 2,
               "unit" => "month"
             }) == :better
    end

    test "fewer visits, a narrower scope, a price rise and an unknown direction are worse" do
      assert Terms.direction(@visits, %{"limit" => 12, "period" => "calendar_month"}, %{
               "limit" => 8,
               "period" => "calendar_month"
             }) == :worse

      assert Terms.direction(@visits, %{"limit" => 12, "period" => "calendar_month"}, %{
               "limit" => 12,
               "period" => "calendar_week"
             }) == :worse

      assert Terms.direction("group_classes.class_types", "all", ["a"]) == :worse
      assert Terms.direction("price", 6000, 6500) == :worse
      assert Terms.direction("price", 6000, 5500) == :better
      assert Terms.direction(@window, nil, 7) == :worse
    end
  end

  describe "timing/4" do
    test "price changes reach a recurring holder from the next period, never a one-charge one" do
      assert Terms.timing("price", 6000, 6500, true) == :next_period
      assert Terms.timing("price", 6000, 5500, true) == :next_period
      assert Terms.timing("price", 6000, 6500, false) == :never
    end

    test "structure never reaches holders; who may buy concerns purchases only" do
      assert Terms.timing("billing_period", "monthly", "quarterly", true) == :never
      assert Terms.timing("terms.joining_fee_cents", 0, 1000, true) == :never
      assert Terms.timing("terms.buyers", "anyone", "staff_only", true) == :purchase_only
    end

    test "a shorter validity or no renewal is never taken from a holder" do
      assert Terms.timing(
               "terms.validity",
               %{"amount" => 2, "unit" => "month"},
               %{"amount" => 1, "unit" => "month"},
               false
             ) == :never

      assert Terms.timing("terms.auto_renew", true, false, true) == :never
      assert Terms.timing("terms.auto_renew", false, true, true) == :now
    end
  end

  describe "plan/5" do
    test "better terms now, a price rise and fewer benefits from the next period start" do
      before =
        terms(6000, %{@visits => %{"limit" => 12, "period" => "calendar_month"}, @window => 7})

      after_change =
        terms(6500, %{@visits => %{"limit" => 8, "period" => "calendar_month"}, @window => 14})

      plan = Terms.plan(holder(), before, after_change, ~D[2026-11-28])

      assert plan.now.fields == %{@window => 14}
      assert plan.next.price_cents == 6500
      assert plan.next.fields == %{@visits => %{"limit" => 8, "period" => "calendar_month"}}
      assert plan.next.effective_on == ~D[2026-12-05]
      assert plan.notes == []
    end

    test "a period already charged ahead keeps its terms" do
      before = terms(6000, %{})
      after_change = terms(6500, %{})

      plan = Terms.plan(holder(), before, after_change, ~D[2026-11-28], [~D[2026-12-05]])
      assert plan.next.effective_on == ~D[2027-01-05]
    end

    test "a member who stopped renewing or is leaving never gets a price rise" do
      before = terms(6000, %{})
      after_change = terms(6500, %{})

      stopped = Terms.plan(holder(%{auto_renew: false}), before, after_change, ~D[2026-11-28])
      assert stopped.next == nil
      assert stopped.notes == [:renewal_stopped]
      assert Enum.all?(stopped.changes, &(&1.timing == :never))

      leaving =
        Terms.plan(
          holder(%{}, %{leaving_on: ~D[2026-12-31]}),
          before,
          after_change,
          ~D[2026-11-28]
        )

      assert leaving.next == nil
    end

    test "a subscription with its own price keeps it" do
      before = terms(5000, %{})
      after_change = terms(6500, %{})

      plan = Terms.plan(holder(), before, after_change, ~D[2026-11-28])
      assert plan.next == nil
      assert plan.notes == [:custom_price]
    end

    test "a longer validity moves a visit pack's end; a smaller pack is never taken" do
      validity = "terms.validity"

      pack =
        holder(%{
          billing_period_snapshot: "one_off",
          starts_on: ~D[2026-11-01],
          ends_on: ~D[2026-11-30],
          params_snapshot: %{
            "entitlement_version" => 2,
            "package_type" => "class_pack",
            "fields" => %{
              validity => %{"amount" => 1, "unit" => "month"},
              @visits => %{"limit" => 10, "period" => "subscription_period"}
            }
          }
        })

      before =
        terms(
          6000,
          %{
            validity => %{"amount" => 1, "unit" => "month"},
            @visits => %{"limit" => 10, "period" => "subscription_period"}
          },
          "one_off"
        )

      after_change =
        terms(
          6000,
          %{
            validity => %{"amount" => 2, "unit" => "month"},
            @visits => %{"limit" => 8, "period" => "subscription_period"}
          },
          "one_off"
        )

      plan = Terms.plan(pack, before, after_change, ~D[2026-11-28])
      assert plan.now.ends_on == ~D[2026-12-31]
      assert plan.next == nil
      assert Enum.find(plan.changes, &(&1.key == @visits)).timing == :never
    end
  end

  describe "merge_pending/5 (ζ)" do
    test "a newer value wins, a key applied now leaves and a key back at its own value drops" do
      h = holder()
      own = own_fields(h)

      pending = %{
        fields: %{@visits => %{"limit" => 8, "period" => "calendar_month"}, @cutoff => 24},
        price_cents: 6500,
        effective_on: ~D[2026-12-05]
      }

      next = %{
        fields: %{@visits => %{"limit" => 12, "period" => "calendar_month"}},
        price_cents: 7000,
        effective_on: ~D[2026-12-05]
      }

      merged = Terms.merge_pending(pending, next, %{@cutoff => 2}, own, 6000)
      assert merged.fields == %{}
      assert merged.price_cents == 7000

      assert Terms.merge_pending(%{pending | price_cents: nil, fields: %{}}, nil, %{}, own, 6000) ==
               nil
    end
  end

  test "apply_terms keeps the type and merges the fields" do
    h = holder()
    applied = Terms.apply_terms(h.subscription, %{@window => 14}, 6500)
    assert applied.price_cents_snapshot == 6500
    assert applied.params_snapshot["package_type"] == "membership"
    assert applied.params_snapshot["fields"][@window] == 14

    assert applied.params_snapshot["fields"][@visits] == %{
             "limit" => 12,
             "period" => "calendar_month"
           }
  end
end
