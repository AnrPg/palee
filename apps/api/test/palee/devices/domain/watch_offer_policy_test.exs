defmodule Palee.Devices.Domain.WatchOfferPolicyTest do
  @moduledoc "ANR's D8 rules (2026-11-01): when the phone puts the timer on the watch."

  use ExUnit.Case, async: true

  alias Palee.Devices.Domain.WatchOfferPolicy, as: Policy

  @open %{
    execution_open?: true,
    watch_connected?: true,
    class_wod?: false,
    checked_in?: false,
    box_member?: true,
    asked_before: 0,
    existing: nil
  }

  test "only while the WOD is open and the watch is connected now" do
    assert {:none, :execution_closed} = Policy.decide(%{@open | execution_open?: false})
    assert {:none, :watch_not_connected} = Policy.decide(%{@open | watch_connected?: false})
  end

  test "a box class WOD only after check-in to that class" do
    assert {:none, :not_checked_in} = Policy.decide(%{@open | class_wod?: true})
    assert {:ask, :first_wods} = Policy.decide(%{@open | class_wod?: true, checked_in?: true})
  end

  test "box members are asked on the first five WODs, then it starts by itself" do
    for n <- 0..4, do: assert({:ask, :first_wods} = Policy.decide(%{@open | asked_before: n}))

    assert {:start, :box_member_after_first_wods} = Policy.decide(%{@open | asked_before: 5})

    # The same conditions still hold after the fifth.
    assert {:none, :not_checked_in} =
             Policy.decide(%{@open | asked_before: 9, class_wod?: true})
  end

  test "free athletes are asked every time" do
    assert {:ask, :free_athlete} = Policy.decide(%{@open | box_member?: false, asked_before: 40})
  end

  test "an execution is decided once" do
    assert {:ask, :not_answered} =
             Policy.decide(%{@open | existing: %{mode: "asked", answer: nil}})

    assert {:start, :answered_yes} =
             Policy.decide(%{@open | existing: %{mode: "asked", answer: "yes"}})

    assert {:none, :answered_no} =
             Policy.decide(%{@open | existing: %{mode: "asked", answer: "no"}})

    assert {:start, :already_started} =
             Policy.decide(%{@open | existing: %{mode: "auto", answer: nil}})
  end

  test "modes and answers" do
    assert Policy.mode({:ask, :first_wods}) == "asked"
    assert Policy.mode({:start, :box_member_after_first_wods}) == "auto"
    assert Policy.mode({:none, :watch_not_connected}) == nil
    assert Policy.answerable?(%{mode: "asked"})
    refute Policy.answerable?(%{mode: "auto"})
    refute Policy.answerable?(nil)
  end
end
