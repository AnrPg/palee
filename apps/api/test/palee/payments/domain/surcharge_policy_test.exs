defmodule Palee.Payments.Domain.SurchargePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Payments.Domain.{SurchargeLaw, SurchargePolicy}

  @today ~D[2026-10-31]
  @consumer_gr %{funding: "credit", country: "GR", commercial: false}
  @commercial %{funding: "credit", country: "GR", commercial: true}
  @us_card %{funding: "credit", country: "US", commercial: false}

  describe "the law" do
    test "EU/EEA: commercial or non-EEA cards only, at cost" do
      regime = SurchargeLaw.regime("GR", nil, @today)
      assert regime.rule == :eea_non_consumer
      assert regime.at_cost
      refute SurchargeLaw.card_allowed?(regime, @consumer_gr)
      assert SurchargeLaw.card_allowed?(regime, @commercial)
      assert SurchargeLaw.card_allowed?(regime, @us_card)
      refute SurchargeLaw.unknown_card_allowed?(regime)
      assert SurchargeLaw.regime("NO", nil, @today).rule == :eea_non_consumer
    end

    test "UK: commercial cards only" do
      regime = SurchargeLaw.regime("GB", nil, @today)
      refute SurchargeLaw.card_allowed?(regime, @us_card)
      assert SurchargeLaw.card_allowed?(regime, @commercial)
    end

    test "US: credit only, a state is needed, banned and capped states" do
      assert SurchargeLaw.regime("US", nil, @today).region_required
      ny = SurchargeLaw.regime("US", "US-NY", @today)
      assert ny.rule == :credit_only and ny.cap_bps == 300
      assert SurchargeLaw.card_allowed?(ny, @us_card)
      refute SurchargeLaw.card_allowed?(ny, %{funding: "debit"})
      assert SurchargeLaw.regime("US", "US-CT", @today).rule == :none
      assert SurchargeLaw.regime("US", "US-CO", @today).cap_bps == 200
    end

    test "Canada: credit only within 2.4 %, not in Quebec" do
      assert SurchargeLaw.regime("CA", "CA-ON", @today).cap_bps == 240
      assert SurchargeLaw.regime("CA", "CA-QC", @today).rule == :none
    end

    test "Australia banned surcharges from 1 October 2026" do
      assert SurchargeLaw.regime("AU", nil, ~D[2026-09-30]).rule == :any
      assert SurchargeLaw.regime("AU", nil, ~D[2026-10-01]).rule == :none
    end

    test "an unknown country gets none" do
      refute SurchargeLaw.allowed?(SurchargeLaw.regime("ZZ", nil, @today))
      refute SurchargeLaw.allowed?(SurchargeLaw.regime(nil, nil, @today))
    end
  end

  describe "settings" do
    test "off by default; off is always allowed" do
      assert %{enabled: false, channels: []} = SurchargePolicy.resolve(nil)

      assert {:ok, %{enabled: false}} =
               SurchargePolicy.change(nil, %{enabled: false}, "ZZ", @today)
    end

    test "refused where the law forbids any surcharge" do
      assert {:error, :card_surcharge_not_allowed, %{regime: "unknown"}} =
               SurchargePolicy.change(
                 nil,
                 %{enabled: true, channels: ["desk"], percent_bps: 150},
                 "ZZ",
                 @today
               )
    end

    test "above the law's cap is refused" do
      assert {:error, :card_surcharge_not_allowed, %{reason: "above_cap"}} =
               SurchargePolicy.change(
                 nil,
                 %{enabled: true, channels: ["online"], percent_bps: 350, region_code: "us-ny"},
                 "US",
                 @today
               )
    end

    test "the US needs the state, the EEA the at-cost confirmation" do
      assert {:error, {:invalid_fields, %{"region_code" => "required"}}} =
               SurchargePolicy.change(
                 nil,
                 %{enabled: true, channels: ["online"], percent_bps: 100},
                 "US",
                 @today
               )

      assert {:error, {:invalid_fields, %{"at_cost_confirmed" => "required"}}} =
               SurchargePolicy.change(
                 nil,
                 %{enabled: true, channels: ["desk"], percent_bps: 100},
                 "GR",
                 @today
               )

      assert {:ok, %{region_code: "US-NY", percent_bps: 250}} =
               SurchargePolicy.change(
                 nil,
                 %{enabled: true, channels: ["online"], percent_bps: 250, region_code: "us-ny"},
                 "US",
                 @today
               )
    end

    test "unknown keys and bad values are refused field by field" do
      assert {:error, {:invalid_fields, errors}} =
               SurchargePolicy.change(
                 nil,
                 %{"colour" => 1, "percent_bps" => -1, "channels" => ["fax"]},
                 "GR",
                 @today
               )

      assert errors == %{
               "colour" => "unknown",
               "percent_bps" => "invalid",
               "channels" => "invalid"
             }
    end
  end

  describe "quotes" do
    setup do
      %{
        settings: %{enabled: true, channels: ["online", "desk"], percent_bps: 250, fixed_cents: 0},
        us: SurchargeLaw.regime("US", "US-NY", @today),
        gr: SurchargeLaw.regime("GR", nil, @today)
      }
    end

    test "a saved US credit card carries the percentage", %{settings: settings, us: us} do
      assert %{applies: true, surcharge_cents: 125, total_cents: 5_125, reason: nil} =
               SurchargePolicy.quote(settings, us, "online", 5_000, @us_card)
    end

    test "a card not chosen yet never carries one", %{settings: settings, us: us} do
      assert %{applies: false, surcharge_cents: 0, total_cents: 5_000, reason: "card_unknown"} =
               SurchargePolicy.quote(settings, us, "online", 5_000, %{})
    end

    test "a Greek consumer card never carries one", %{settings: settings, gr: gr} do
      assert %{applies: false, reason: "card_not_surchargeable"} =
               SurchargePolicy.quote(settings, gr, "desk", 5_000, @consumer_gr)

      assert %{applies: true, surcharge_cents: 125} =
               SurchargePolicy.quote(settings, gr, "desk", 5_000, @commercial)
    end

    test "the cap limits a fixed part too", %{us: us} do
      settings = %{enabled: true, channels: ["online"], percent_bps: 300, fixed_cents: 50}

      assert %{surcharge_cents: 30} =
               SurchargePolicy.quote(settings, us, "online", 1_000, @us_card)
    end

    test "a channel left out or the setting off", %{settings: settings, us: us} do
      assert %{reason: "channel_off"} =
               SurchargePolicy.quote(
                 %{settings | channels: ["desk"]},
                 us,
                 "online",
                 100,
                 @us_card
               )

      assert %{reason: "off"} = SurchargePolicy.quote(nil, us, "online", 100, @us_card)
    end

    test "staff may not type more than the quote", %{settings: settings, gr: gr} do
      assert :ok = SurchargePolicy.check_desk(settings, gr, 5_000, 125, @commercial)

      assert {:error, :card_surcharge_not_allowed, %{reason: "above_quote", max_cents: 125}} =
               SurchargePolicy.check_desk(settings, gr, 5_000, 126, @commercial)

      assert {:error, :card_surcharge_not_allowed, %{reason: "card_not_surchargeable"}} =
               SurchargePolicy.check_desk(settings, gr, 5_000, 100, @consumer_gr)
    end
  end

  describe "Tap to Pay" do
    test "the provider decides until the owner chose; off or a ban skips it" do
      gr = SurchargeLaw.regime("GR", nil, @today)
      refute SurchargePolicy.terminal_skip?(nil, gr)
      assert SurchargePolicy.terminal_skip?(%{enabled: false}, gr)
      refute SurchargePolicy.terminal_skip?(%{enabled: true, channels: ["terminal"]}, gr)

      assert SurchargePolicy.terminal_skip?(
               %{enabled: true, channels: ["terminal"]},
               SurchargeLaw.regime("AU", nil, @today)
             )
    end
  end
end
