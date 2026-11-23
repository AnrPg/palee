defmodule Palee.BoxScreens.Domain.FocusTest do
  use ExUnit.Case, async: true

  alias Palee.BoxScreens.Domain.Focus

  @seven %{
    id: "a",
    scheduled_at: ~U[2027-02-09 07:00:00Z],
    duration_minutes: 60,
    cancelled: false
  }
  @eight %{
    id: "b",
    scheduled_at: ~U[2027-02-09 08:00:00Z],
    duration_minutes: 60,
    cancelled: false
  }
  @eighteen %{
    id: "c",
    scheduled_at: ~U[2027-02-09 18:00:00Z],
    duration_minutes: 60,
    cancelled: false
  }

  @day [@seven, @eight, @eighteen]

  defp auto(at), do: Focus.resolve(@day, nil, at)

  test "before the first class: its preview" do
    assert %{source: "auto", view: "preview", slot_id: "a"} = auto(~U[2027-02-09 05:00:00Z])
  end

  test "during a class: its timer, even right after a previous one ended" do
    assert %{view: "timer", slot_id: "a"} = auto(~U[2027-02-09 07:00:00Z])
    assert %{view: "timer", slot_id: "b"} = auto(~U[2027-02-09 08:05:00Z])
  end

  test "up to 30 minutes after a class: its results, then the next preview" do
    assert %{view: "results", slot_id: "b"} = auto(~U[2027-02-09 09:00:00Z])
    assert %{view: "results", slot_id: "b"} = auto(~U[2027-02-09 09:29:59Z])
    assert %{view: "preview", slot_id: "c"} = auto(~U[2027-02-09 09:30:00Z])
  end

  test "after the last class's results: idle" do
    assert %{view: "results", slot_id: "c"} = auto(~U[2027-02-09 19:10:00Z])
    assert %{view: "idle", slot_id: nil} = auto(~U[2027-02-09 19:31:00Z])
  end

  test "cancelled classes are skipped" do
    day = [%{@seven | cancelled: true}, @eight]

    assert %{view: "preview", slot_id: "b"} =
             Focus.resolve(day, nil, ~U[2027-02-09 07:10:00Z])
  end

  test "a staff override wins while its class is on the screen" do
    override = %{view: "leaderboard", slot_id: "c", until: nil}

    assert %{source: "staff", view: "leaderboard", slot_id: "c", until: nil} =
             Focus.resolve(@day, override, ~U[2027-02-09 07:10:00Z])

    assert %{source: "staff", view: "bookings", slot_id: nil} =
             Focus.resolve(
               @day,
               %{view: "bookings", slot_id: nil, until: nil},
               ~U[2027-02-09 07:10:00Z]
             )

    gone = %{view: "class", slot_id: "zz", until: nil}

    assert %{source: "auto", view: "timer", slot_id: "a"} =
             Focus.resolve(@day, gone, ~U[2027-02-09 07:10:00Z])
  end

  describe "ADR-746: classes at the same time" do
    @hall %{
      id: "hall",
      space_id: "space-hall",
      scheduled_at: ~U[2027-02-09 18:00:00Z],
      duration_minutes: 60,
      cancelled: false
    }
    @yard %{
      id: "yard",
      space_id: "space-yard",
      scheduled_at: ~U[2027-02-09 18:00:00Z],
      duration_minutes: 60,
      cancelled: false
    }
    @at ~U[2027-02-09 18:10:00Z]

    test "a screen in a space shows that space's class" do
      assert %{view: "timer", slot_id: "yard", split_slot_id: nil} =
               Focus.resolve([@hall, @yard], nil, @at, %{space_id: "space-yard"})

      assert %{view: "timer", slot_id: "hall"} =
               Focus.resolve([@hall, @yard], nil, @at, %{space_id: "space-hall"})
    end

    test "a space with no class falls back to the whole branch" do
      assert %{view: "timer", slot_id: slot_id} =
               Focus.resolve([@hall, @yard], nil, @at, %{space_id: "space-office"})

      assert slot_id in ["hall", "yard"]
    end

    test "a shared screen shows two running classes side by side" do
      assert %{view: "timer", slot_id: first, split_slot_id: second} =
               Focus.resolve([@hall, @yard], nil, @at, %{concurrent_mode: "split"})

      assert Enum.sort([first, second]) == ["hall", "yard"]
    end

    test "a shared screen with one class running shows just that class" do
      assert %{view: "timer", slot_id: "a", split_slot_id: nil} =
               Focus.resolve(@day, nil, ~U[2027-02-09 07:10:00Z], %{concurrent_mode: "split"})
    end

    test "a staff pin keeps its WOD and the class it shares with" do
      override = %{
        view: "timer",
        slot_id: "hall",
        until: nil,
        workout_id: "w2",
        split_slot_id: "yard"
      }

      assert %{source: "staff", slot_id: "hall", workout_id: "w2", split_slot_id: "yard"} =
               Focus.resolve([@hall, @yard], override, @at)
    end
  end
end
