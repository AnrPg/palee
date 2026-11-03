defmodule Palee.Nutrition.Domain.FoodSharePolicyTest do
  @moduledoc "ADR-421 addendum: what a share holds, its outbox and the members' cache row."

  use ExUnit.Case, async: true

  alias Palee.Nutrition.Domain.{FoodCachePolicy, FoodSharePolicy}

  @now ~U[2026-11-03 10:00:00.000000Z]

  @food %{
    barcode: "5201234500006",
    name: "Παξιμάδι",
    brand: "Φούρνος",
    serving_label: "2 φέτες",
    portion_hint: "carbs",
    note: "του πρωινού",
    nutrients: %{"carbohydrates" => 70.0},
    user_id: "someone"
  }

  test "a share holds the product only, and its cache row is from members, found, unattributed" do
    share = FoodSharePolicy.share_attrs(@food, "user-1", "el", @now)

    assert %{barcode: "5201234500006", user_id: "user-1", off_status: "queued"} = share
    refute Map.has_key?(share, :note)

    cache = FoodSharePolicy.cache_attrs(share, @now)
    assert %{status: "found", source: "palee_members", name: "Παξιμάδι", fetched_at: @now} = cache
    refute Map.has_key?(cache, :user_id)
    refute Map.has_key?(cache, :note)
  end

  test "only product barcodes, and the language of the person in two letters" do
    assert FoodSharePolicy.shareable_barcode?("5201234500006", false)
    refute FoodSharePolicy.shareable_barcode?("2001234000000", true)
    refute FoodSharePolicy.shareable_barcode?(nil, false)

    assert FoodSharePolicy.language("pt-PT") == "pt"
    assert FoodSharePolicy.language("en") == "en"
    assert FoodSharePolicy.language("xx") == "el"
    assert FoodSharePolicy.language(nil) == "el"
  end

  test "the outbox: sent, exists, refused for good, retried with back-off then failed" do
    assert %{off_status: "sent", off_sent_at: @now} =
             FoodSharePolicy.after_contribution(:ok, %{off_attempts: 1}, @now)

    assert %{off_status: "exists"} =
             FoodSharePolicy.after_contribution({:error, :exists}, %{off_attempts: 1}, @now)

    assert %{off_status: "failed"} =
             FoodSharePolicy.after_contribution(
               {:error, {:rejected, "bad"}},
               %{off_attempts: 1},
               @now
             )

    assert %{off_status: "queued", off_next_attempt_at: next} =
             FoodSharePolicy.after_contribution(
               {:error, {:transient, {:http, 503}}},
               %{off_attempts: 2},
               @now
             )

    assert DateTime.diff(next, @now) == 5 * 60

    assert %{off_status: "failed"} =
             FoodSharePolicy.after_contribution({:error, :timeout}, %{off_attempts: 6}, @now)
  end

  test "a members' product stays when a refresh finds it nowhere, a public source replaces it" do
    row = %{source: "palee_members", status: "pending", name: "Παξιμάδι", attempts: 1}

    assert %{status: "found", fetched_at: @now} =
             FoodCachePolicy.after_lookup({:error, :not_found}, row, @now)

    assert %{status: "found"} =
             FoodCachePolicy.after_lookup({:error, {:transient, :x}}, row, @now)

    assert %{status: "found", source: "open_food_facts", name: "Από OFF"} =
             FoodCachePolicy.after_lookup(
               {:ok, %{source: "open_food_facts", name: "Από OFF"}},
               row,
               @now
             )

    assert %{source: "Palee members", licence: "ODbL-1.0"} =
             FoodCachePolicy.attribution("palee_members", "5201234500006")
  end
end
