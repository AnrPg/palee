defmodule Palee.Organizations.Domain.BusinessFeaturesTest do
  @moduledoc "ADR-470: the pure rules behind «is this feature on for this business»."
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.BusinessFeatures

  @today ~D[2026-11-04]

  test "nothing known means every feature off, with every key present" do
    features = BusinessFeatures.evaluate(%{}, @today)

    assert Enum.sort(Map.keys(features)) == Enum.sort(BusinessFeatures.keys())
    assert Enum.all?(features, fn {_key, on} -> on == false end)
  end

  test "a payment purpose is on only with an active account and the purpose left on" do
    purposes = %{"packages" => true, "autopay" => false}

    off = BusinessFeatures.evaluate(%{payments_active: false, payment_purposes: purposes}, @today)
    refute off["online_payments"]
    refute off["online_packages"]

    on = BusinessFeatures.evaluate(%{payments_active: true, payment_purposes: purposes}, @today)
    assert on["online_payments"]
    assert on["online_packages"]
    refute on["card_autopay"]
  end

  test "promotions need a running, active campaign with an active code" do
    running = %{id: "c1", active: true, starts_on: ~D[2026-11-01], ends_on: nil}
    ended = %{id: "c2", active: true, starts_on: nil, ends_on: ~D[2026-11-03]}
    future = %{id: "c3", active: true, starts_on: ~D[2026-11-05], ends_on: nil}
    paused = %{id: "c4", active: false, starts_on: nil, ends_on: nil}

    code = fn campaign, active -> %{promotion_campaign_id: campaign, active: active} end

    assert BusinessFeatures.promotion_live?([running], [code.("c1", true)], @today)
    refute BusinessFeatures.promotion_live?([running], [code.("c1", false)], @today)

    refute BusinessFeatures.promotion_live?(
             [ended, future, paused],
             [code.("c2", true), code.("c3", true), code.("c4", true)],
             @today
           )

    refute BusinessFeatures.promotion_live?([running], [], @today)
  end

  test "a branch filter keeps campaigns and floor plans that cover the branch or the whole box" do
    only_a = %{
      id: "c1",
      active: true,
      starts_on: nil,
      ends_on: nil,
      location_scope: %{all_locations: false, location_ids: ["a"]}
    }

    facts = %{
      promotion_campaigns: [only_a],
      promotion_codes: [%{promotion_campaign_id: "c1", active: true}],
      floor_plans: [%{id: "p1", location_id: "a"}]
    }

    assert BusinessFeatures.evaluate(facts, @today)["promotions"]
    assert BusinessFeatures.evaluate(facts, @today, ["a"])["promotions"]
    refute BusinessFeatures.evaluate(facts, @today, ["b"])["promotions"]
    assert BusinessFeatures.evaluate(facts, @today, ["a"])["floor_plan"]
    refute BusinessFeatures.evaluate(facts, @today, ["b"])["floor_plan"]

    whole_box = %{facts | floor_plans: [%{id: "p2", location_id: nil}]}
    assert BusinessFeatures.evaluate(whole_box, @today, ["b"])["floor_plan"]
  end

  test "branches means two or more active branches; modules follow the enabled list" do
    refute BusinessFeatures.evaluate(%{active_locations: 1}, @today)["branches"]
    assert BusinessFeatures.evaluate(%{active_locations: 2}, @today)["branches"]

    features = BusinessFeatures.evaluate(%{enabled_modules: ["corporate_clients"]}, @today)
    assert features["module_corporate_clients"]
    refute features["module_group_classes"]
  end

  test "referrals, perks and trials" do
    features =
      BusinessFeatures.evaluate(
        %{referral_program_active: true, published_perks: 1, trials_enabled: true},
        @today
      )

    assert features["referrals"] and features["perks"] and features["trials"]
  end
end
