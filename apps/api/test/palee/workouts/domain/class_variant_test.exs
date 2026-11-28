defmodule Palee.Workouts.Domain.ClassVariantTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.ClassVariant

  test "a variant stands in for its source when it is a class WOD, else the member's WOD, else the first" do
    assert ClassVariant.stands_in_for("b", ["a", "b"], "a") == "b"
    assert ClassVariant.stands_in_for("library", ["a", "b"], "b") == "b"
    assert ClassVariant.stands_in_for(nil, ["a", "b"], nil) == "a"
    assert ClassVariant.stands_in_for(nil, [], nil) == nil
  end

  test "stale says when the class WOD left the class or reads differently" do
    variant = %{variant_of_workout_id: "a", variant_source_hash: "h1"}

    assert ClassVariant.stale(variant, ["a"], %{"a" => "h1"}) == nil
    assert ClassVariant.stale(variant, ["a"], %{"a" => "h2"}) == "changed"
    assert ClassVariant.stale(variant, ["b"], %{}) == "removed"
    # Made before ADR-785: nothing to compare.
    assert ClassVariant.stale(%{variant_of_workout_id: nil}, ["a"], %{}) == nil

    assert ClassVariant.stale(%{variant_of_workout_id: "a", variant_source_hash: nil}, ["a"], %{
             "a" => "h"
           }) == nil
  end

  test "active until the member goes back to a class WOD" do
    assert ClassVariant.active?(%{set_aside_at: nil})
    refute ClassVariant.active?(%{set_aside_at: ~U[2026-11-28 10:00:00Z]})
  end
end
