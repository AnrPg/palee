defmodule Palee.Organizations.Domain.BusinessFeatures do
  @moduledoc """
  Which optional features a business (gym, branch, independent coach) has
  switched on (ADR-470). One answer for every screen: a chip, menu entry,
  widget, KPI or settings section that only makes sense with a feature on is
  shown only when this says the feature is on (or, for a work list, when it
  still holds rows someone must handle).

  This module is pure: it turns the facts the application layer read from
  each context into `%{key => boolean}`. A new feature is one new key here,
  one new fact in `Palee.Application.BusinessFeatures` and one entry in the
  web helper (`lib/business-features.ts`).

  Keys:

    * `online_payments` – a payment provider (Stripe, Viva) is connected and
      active;
    * `online_packages`, `card_autopay`, `online_drop_in`, `online_shop`,
      `online_personal_training`, `online_programmes` – that purpose is paid
      online (the account is active and the business left the purpose on,
      ADR-260). `card_autopay` is the saved-card renewals and bills, the only
      source of failed charges;
    * `referrals` – a referral programme is active;
    * `promotions` – a promotion campaign runs today and has an active code;
    * `perks` – at least one partner perk is published;
    * `trials` – trial visits are on;
    * `branches` – the business has two or more active branches, so branch
      pickers, «Παράρτημα» labels and per-branch splits mean something;
    * `floor_plan` – a floor plan is uploaded (for the filtered branches, or
      the whole box), so «Δες στην κάτοψη», pins and plan toggles have
      something to show;
    * `module_<key>` – the package module is on (group classes, personal
      training, corporate clients …, ADR-098).
  """

  @payment_purposes %{
    "online_packages" => "packages",
    "card_autopay" => "autopay",
    "online_drop_in" => "drop_in",
    "online_shop" => "shop",
    "online_personal_training" => "personal_training",
    "online_programmes" => "programmes"
  }

  @modules ~w(group_classes online_coaching open_gym events personal_training digital_content corporate_clients)

  @keys ["online_payments"] ++
          Enum.sort(Map.keys(@payment_purposes)) ++
          ~w(referrals promotions perks trials branches floor_plan) ++
          Enum.map(@modules, &"module_#{&1}")

  @doc "Every feature key, in a stable order (the API lists them all)."
  def keys, do: @keys

  @doc "The package modules a `module_<key>` feature can name."
  def modules, do: @modules

  @doc """
  The answer for one business. `facts`:

    * `:payments_active` – boolean; `:payment_purposes` – `%{purpose => boolean}`;
    * `:referral_program_active` – boolean;
    * `:promotion_campaigns`, `:promotion_codes` – Finance's normalized rows;
    * `:published_perks` – a count; `:trials_enabled` – boolean;
    * `:active_locations` – a count; `:floor_plans` – Spaces' plan rows
      (each with `location_id`, nil for a whole-box plan);
    * `:enabled_modules` – the package module keys that are on.

  A missing fact counts as off, never as on. `location_ids` (a branch
  filter, ADR-186 §7) narrows the features a branch can have on its own:
  promotions, which may cover some branches, and the floor plan, which
  belongs to one branch or to the whole box. Everything else is
  business-wide (one payment account, one referral programme …).
  """
  def evaluate(facts, %Date{} = today, location_ids \\ nil) when is_map(facts) do
    payments_active = Map.get(facts, :payments_active) == true
    purposes = Map.get(facts, :payment_purposes) || %{}
    modules = MapSet.new(Map.get(facts, :enabled_modules) || [])

    purpose_features =
      Map.new(@payment_purposes, fn {key, purpose} ->
        {key, payments_active and Map.get(purposes, purpose) == true}
      end)

    module_features = Map.new(@modules, &{"module_#{&1}", MapSet.member?(modules, &1)})

    %{
      "online_payments" => payments_active,
      "referrals" => Map.get(facts, :referral_program_active) == true,
      "promotions" =>
        promotion_live?(
          facts |> Map.get(:promotion_campaigns, []) |> List.wrap() |> covering(location_ids),
          Map.get(facts, :promotion_codes) || [],
          today
        ),
      "perks" => (Map.get(facts, :published_perks) || 0) > 0,
      "trials" => Map.get(facts, :trials_enabled) == true,
      "branches" => (Map.get(facts, :active_locations) || 0) > 1,
      "floor_plan" =>
        facts
        |> Map.get(:floor_plans, [])
        |> List.wrap()
        |> plans_for(location_ids)
        |> Enum.any?()
    }
    |> Map.merge(purpose_features)
    |> Map.merge(module_features)
  end

  @doc """
  Whether a member can use a promotion code today: a campaign that is active
  and runs today (open ends count as running) has at least one active code.
  """
  def promotion_live?(campaigns, codes, %Date{} = today) do
    running =
      campaigns
      |> Enum.filter(&campaign_running?(&1, today))
      |> MapSet.new(& &1.id)

    Enum.any?(codes, fn code ->
      Map.get(code, :active) == true and
        MapSet.member?(running, Map.get(code, :promotion_campaign_id))
    end)
  end

  @doc "The campaigns valid at one of `location_ids` (all of them when nil or empty)."
  def covering(campaigns, location_ids) when location_ids in [nil, []], do: campaigns

  def covering(campaigns, location_ids) do
    wanted = MapSet.new(location_ids)

    Enum.filter(campaigns, fn campaign ->
      case Map.get(campaign, :location_scope) do
        %{all_locations: false, location_ids: ids} ->
          Enum.any?(ids || [], &MapSet.member?(wanted, &1))

        _everywhere ->
          true
      end
    end)
  end

  @doc "The plans of `location_ids` plus whole-box plans (every plan when nil or empty)."
  def plans_for(plans, location_ids) when location_ids in [nil, []], do: plans

  def plans_for(plans, location_ids) do
    wanted = MapSet.new(location_ids)

    Enum.filter(plans, fn plan ->
      case Map.get(plan, :location_id) do
        nil -> true
        id -> MapSet.member?(wanted, id)
      end
    end)
  end

  defp campaign_running?(campaign, today) do
    Map.get(campaign, :active) == true and
      not after?(Map.get(campaign, :starts_on), today) and
      not before?(Map.get(campaign, :ends_on), today)
  end

  defp after?(%Date{} = date, today), do: Date.compare(date, today) == :gt
  defp after?(_none, _today), do: false

  defp before?(%Date{} = date, today), do: Date.compare(date, today) == :lt
  defp before?(_none, _today), do: false
end
