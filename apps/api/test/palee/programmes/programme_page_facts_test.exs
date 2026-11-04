defmodule Palee.Programmes.Domain.ProgrammePageFactsTest do
  @moduledoc """
  ADR-541/542/544: the cover's edit, «κύριος εξοπλισμός» and «περίπου ανά
  προπόνηση», and what a draft still lacks.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Palee.Programmes.Domain.{ProgrammeCover, ProgrammeFacts, ProgrammeReadiness}
  alias Palee.Workouts.Domain.ExerciseEquipment

  @order ExerciseEquipment.keys()

  defp days(rows), do: Enum.map(rows, fn {day, id} -> %{"day" => day, "workout_id" => id} end)

  describe "facts" do
    test "equipment ranks by sessions, ties in vocabulary order, at most 5" do
      workouts = %{
        "a" => %{equipment: ["barbell", "box"], duration_seconds: 2_700},
        "b" => %{equipment: ["kettlebell", "box"], duration_seconds: 1_800},
        "c" => %{equipment: ["rower", "dumbbell", "rings", "jump_rope"], duration_seconds: 600}
      }

      facts =
        ProgrammeFacts.derive(days([{0, "a"}, {2, "b"}, {4, "a"}, {7, "c"}]), workouts, @order)

      assert facts["equipment"] == ["box", "barbell", "dumbbell", "kettlebell", "rings"]
      # (45 + 30 + 45 + 10) / 4 = 32.5 minutes, rounded to 5.
      assert facts["minutes_per_session"] == 35
    end

    test "WODs of one day add up; a WOD without a duration means no minutes at all" do
      workouts = %{
        "a" => %{equipment: [], duration_seconds: 1_200},
        "b" => %{equipment: [], duration_seconds: 1_800},
        "c" => %{equipment: ["none"], duration_seconds: nil}
      }

      assert %{"minutes_per_session" => 50} =
               ProgrammeFacts.derive(days([{0, "a"}, {0, "b"}]), workouts, @order)

      assert %{"minutes_per_session" => nil} =
               ProgrammeFacts.derive(days([{0, "a"}, {1, "c"}]), workouts, @order)

      # An unknown WOD (deleted, other box) has neither.
      assert %{"minutes_per_session" => nil, "equipment" => []} =
               ProgrammeFacts.derive(days([{0, "x"}]), workouts, @order)

      assert %{"minutes_per_session" => nil, "equipment" => []} =
               ProgrammeFacts.derive([], workouts, @order)
    end

    test "`none` shows only when nothing else is needed" do
      workouts = %{
        "a" => %{equipment: ["none"], duration_seconds: 600},
        "b" => %{equipment: ["barbell"], duration_seconds: 600}
      }

      assert %{"equipment" => ["none"]} =
               ProgrammeFacts.derive(days([{0, "a"}]), workouts, @order)

      assert %{"equipment" => ["barbell"]} =
               ProgrammeFacts.derive(days([{0, "a"}, {1, "b"}]), workouts, @order)
    end

    test "the author's choice wins key by key" do
      derived = ["barbell", "box", "rower"]

      assert ProgrammeFacts.effective_equipment(derived, [], []) == derived

      assert ProgrammeFacts.effective_equipment(derived, ["rings", "box"], ["rower"]) ==
               ["rings", "box", "barbell"]

      assert :ok = ProgrammeFacts.check_lists(["rings"], ["rower"], @order)
      assert :ok = ProgrammeFacts.check_lists(nil, nil, @order)
      assert {:error, :invalid_equipment} = ProgrammeFacts.check_lists(["Barbell"], [], @order)
      assert {:error, :invalid_equipment} = ProgrammeFacts.check_lists([], "rower", @order)

      assert {:error, :invalid_equipment} =
               ProgrammeFacts.check_lists(Enum.take(@order, 11), [], @order)
    end

    property "added keys always show and removed derived ones never do" do
      check all(
              derived <- uniq_list_of(member_of(@order), max_length: 5),
              added <- uniq_list_of(member_of(@order), max_length: 5),
              removed <- uniq_list_of(member_of(@order), max_length: 5)
            ) do
        shown = ProgrammeFacts.effective_equipment(derived, added, removed)

        assert Enum.take(shown, length(added)) == added
        assert Enum.uniq(shown) == shown
        assert Enum.all?(removed -- added, &(&1 not in shown))
        assert Enum.all?(derived -- removed, &(&1 in shown))
      end
    end
  end

  describe "readiness" do
    defp draft(attrs) do
      Map.merge(
        %{
          title: "Strength",
          summary: "Six weeks",
          price_cents: 3_900,
          draft_weeks: 3,
          draft_days: []
        },
        attrs
      )
    end

    test "a ready draft lacks nothing" do
      days = days([{0, "a"}, {8, "a"}, {15, "b"}])
      assert ProgrammeReadiness.check(draft(%{draft_days: days})) == []
    end

    test "lists blocking items first and the empty weeks by number" do
      assert [
               %{key: "price", blocking: true, weeks: []},
               %{key: "days", blocking: true},
               %{key: "summary", blocking: false}
             ] = ProgrammeReadiness.check(draft(%{price_cents: 0, summary: "  "}))

      assert [%{key: "empty_weeks", blocking: false, weeks: [2, 3]}] =
               ProgrammeReadiness.check(draft(%{draft_days: days([{3, "a"}])}))
    end
  end

  describe "cover" do
    test "the edit is normalised with neutral defaults" do
      assert {:ok,
              %{
                "rotation" => 0,
                "zoom" => 1.0,
                "brightness" => 1.0,
                "crop" => %{"x" => +0.0, "width" => 1.0}
              }} = ProgrammeCover.normalize_edit(nil)

      assert {:ok, %{"rotation" => 90, "zoom" => 1.5, "brightness" => 1.2}} =
               ProgrammeCover.normalize_edit(%{
                 "rotation" => 90,
                 "zoom" => 1.5,
                 "brightness" => 1.2,
                 "crop" => %{"x" => 0, "y" => 0.1, "width" => 1, "height" => 0.5}
               })

      for bad <- [
            %{"rotation" => 45},
            %{"zoom" => 0.5},
            %{"zoom" => 5},
            %{"brightness" => 2},
            %{"crop" => %{"x" => 0.5, "y" => 0, "width" => 0.6, "height" => 0.5}},
            %{"crop" => %{"x" => 0, "y" => 0}},
            "edit"
          ] do
        assert {:error, :invalid_cover_edit} = ProgrammeCover.normalize_edit(bad)
      end
    end

    test "the rendered cover and the crop are 16:9" do
      {:ok, whole} = ProgrammeCover.normalize_edit(nil)
      assert :ok = ProgrammeCover.check_size(%{width: 1_600, height: 900}, nil, whole)

      assert {:error, :invalid_cover_size} =
               ProgrammeCover.check_size(%{width: 1_000, height: 1_000}, nil, whole)

      assert {:error, :invalid_cover_size} =
               ProgrammeCover.check_size(%{width: 160, height: 90}, nil, whole)

      # A 3000×4000 portrait photo, rotated: 4000×3000; a full-width band of
      # 4000×2250 is 0.75 of its height.
      {:ok, band} =
        ProgrammeCover.normalize_edit(%{
          "rotation" => 90,
          "crop" => %{"x" => 0, "y" => 0.1, "width" => 1, "height" => 0.75}
        })

      portrait = %{width: 3_000, height: 4_000}
      assert :ok = ProgrammeCover.check_size(%{width: 1_920, height: 1_080}, portrait, band)

      {:ok, unrotated} =
        ProgrammeCover.normalize_edit(%{
          "crop" => %{"x" => 0, "y" => 0.1, "width" => 1, "height" => 0.75}
        })

      assert {:error, :invalid_cover_size} =
               ProgrammeCover.check_size(%{width: 1_920, height: 1_080}, portrait, unrotated)
    end
  end
end
