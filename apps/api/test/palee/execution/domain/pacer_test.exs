defmodule Palee.Execution.Domain.PacerTest do
  @moduledoc "ADR-374: split marks and the pace line of the previous attempt."

  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.{Pacer, SplitMarks}

  # An AMRAP (one countdown), a transition, then a 3-round EMOM.
  @segments [
    %{section_id: "a", section_name: "AMRAP 10", kind: :countdown, phase: "work", round: nil},
    %{
      section_id: "a:transition",
      section_name: "AMRAP 10",
      kind: :countdown,
      phase: "transition"
    },
    %{
      section_id: "b",
      section_name: "EMOM",
      kind: :countdown,
      phase: "work",
      round: 1,
      total_rounds: 3
    },
    %{
      section_id: "b",
      section_name: "EMOM",
      kind: :countdown,
      phase: "work",
      round: 2,
      total_rounds: 3
    },
    %{
      section_id: "b",
      section_name: "EMOM",
      kind: :countdown,
      phase: "work",
      round: 3,
      total_rounds: 3
    }
  ]

  describe "SplitMarks.cast/2" do
    test "places marks in their section, round and phase" do
      assert {:ok, rows} =
               SplitMarks.cast(
                 [
                   %{"segment_index" => 0, "round" => 1, "elapsed_ms" => 95_000},
                   %{segment_index: 0, round: 2, elapsed_ms: 190_000},
                   %{segment_index: 0, elapsed_ms: 600_000},
                   %{segment_index: 1, elapsed_ms: 660_000},
                   %{segment_index: 3, elapsed_ms: 780_000}
                 ],
                 @segments
               )

      assert [
               %{section_ordinal: 0, round: 1, phase: "work"},
               %{section_ordinal: 0, round: 2},
               %{section_ordinal: 0, round: 0},
               %{section_ordinal: 0, phase: "transition", section_id: "a:transition"},
               %{section_ordinal: 1, round: 2, section_id: "b"}
             ] = rows
    end

    test "drops repeats of the same segment and round" do
      mark = %{segment_index: 0, round: 1, elapsed_ms: 95_000}
      assert {:ok, [_one]} = SplitMarks.cast([mark, mark], @segments)
    end

    test "refuses marks that don't fit the timer" do
      for marks <- [
            [],
            [%{segment_index: 9, elapsed_ms: 1}],
            [%{segment_index: 2, round: 4, elapsed_ms: 1}],
            [%{segment_index: 0, elapsed_ms: -1}],
            [%{segment_index: "0", elapsed_ms: 1}],
            List.duplicate(%{segment_index: 0, elapsed_ms: 1}, 501),
            "nope"
          ] do
        assert {:error, :invalid_split_marks} = SplitMarks.cast(marks, @segments)
      end
    end
  end

  describe "SplitMarks.from_progress/3" do
    @keyed Enum.with_index(@segments, fn segment, index ->
             Map.put(segment, :segment_key, "segment:#{index}")
           end)

    test "segments moved past end, new AMRAP counts finish rounds, all at the update's time" do
      previous = %{current_segment_index: 0, segment_cycle_counts: %{"segment:0" => 1}}

      updated = %{
        current_segment_index: 2,
        total_elapsed_ms: 660_000,
        segment_cycle_counts: %{"segment:0" => 3}
      }

      rows = SplitMarks.from_progress(previous, updated, @keyed)

      assert Enum.map(rows, &{&1.segment_index, &1.round, &1.elapsed_ms}) == [
               {0, 0, 660_000},
               {1, 0, 660_000},
               {0, 2, 660_000},
               {0, 3, 660_000}
             ]
    end

    test "nothing new, an unknown segment key or rounds a fixed segment lacks give no marks" do
      same = %{current_segment_index: 2, total_elapsed_ms: 1, segment_cycle_counts: %{}}
      assert SplitMarks.from_progress(same, same, @keyed) == []

      forged = %{same | segment_cycle_counts: %{"forged" => 4}}
      assert SplitMarks.from_progress(same, forged, @keyed) == []

      # The EMOM segment has 3 rounds: counts beyond them are dropped.
      emom = %{same | segment_cycle_counts: %{"segment:2" => 9}}

      assert [1, 2, 3] =
               same |> SplitMarks.from_progress(emom, @keyed) |> Enum.map(& &1.round)

      assert SplitMarks.from_progress(same, emom, []) == []
    end

    test "ADR-549: the device's round marks give each round its exact time" do
      previous = %{current_segment_index: 0, segment_cycle_counts: %{"segment:0" => 1}}

      updated = %{
        current_segment_index: 0,
        total_elapsed_ms: 300_000,
        segment_cycle_counts: %{"segment:0" => 3}
      }

      marks = [
        %{"segment_key" => "segment:0", "round" => 2, "elapsed_ms" => 130_000},
        # beyond the update's clock, an unknown segment, a bad round: ignored
        %{"segment_key" => "segment:0", "round" => 3, "elapsed_ms" => 900_000},
        %{"segment_key" => "forged", "round" => 3, "elapsed_ms" => 200_000},
        %{"segment_key" => "segment:0", "round" => 0, "elapsed_ms" => 10}
      ]

      rows = SplitMarks.from_progress(previous, updated, @keyed, marks)

      assert Enum.map(rows, &{&1.round, &1.elapsed_ms}) == [{2, 130_000}, {3, 300_000}]
    end
  end

  describe "pick_previous/2" do
    test "the newest earlier attempt with the same identity, same scale first" do
      start = ~U[2026-10-30 10:00:00Z]

      candidates = [
        %{
          id: "now",
          key: "benchmark:fran",
          status: :active,
          completed_at_utc: nil,
          scale_level_slug: "rx"
        },
        %{
          id: "old-rx",
          key: "benchmark:fran",
          status: :completed,
          completed_at_utc: ~U[2026-09-01 10:00:00Z],
          scale_level_slug: "rx"
        },
        %{
          id: "new-scaled",
          key: "benchmark:fran",
          status: "completed",
          completed_at_utc: ~U[2026-10-01 10:00:00Z],
          scale_level_slug: "scaled"
        },
        %{
          id: "grace",
          key: "benchmark:grace",
          status: :completed,
          completed_at_utc: ~U[2026-10-02 10:00:00Z],
          scale_level_slug: "rx"
        },
        %{
          id: "later",
          key: "benchmark:fran",
          status: :completed,
          completed_at_utc: ~U[2026-10-31 10:00:00Z],
          scale_level_slug: "rx"
        }
      ]

      current = %{id: "now", key: "benchmark:fran", started_at_utc: start, scale_level_slug: "rx"}
      assert %{id: "old-rx"} = Pacer.pick_previous(candidates, current)

      assert %{id: "new-scaled"} =
               Pacer.pick_previous(candidates, %{current | scale_level_slug: "scaled"})

      assert Pacer.pick_previous(candidates, %{current | key: nil}) == nil
      assert Pacer.pick_previous([], current) == nil
    end
  end

  describe "compare/3" do
    test "aligns checkpoints by section, phase and round; negative is ahead" do
      ghost_splits = [
        split(0, 1, 100_000),
        split(0, 2, 200_000),
        split(1, 1, 360_000)
      ]

      current_splits = [split(0, 1, 90_000), split(0, 2, 210_000)]
      ordinals = SplitMarks.section_ordinals(@segments)

      ghost = %{
        checkpoints: Pacer.checkpoints(ghost_splits),
        section_times: Pacer.section_times(%{"a" => 600_000, "b" => 180_000}, ordinals),
        total_ms: 780_000,
        completed?: true
      }

      current = %{
        checkpoints: Pacer.checkpoints(current_splits),
        section_times: Pacer.section_times(%{"a" => 590_000, "a:transition" => 5_000}, ordinals),
        total_ms: 595_000,
        completed?: false
      }

      result = Pacer.compare(ghost, current, Pacer.section_names(@segments))

      assert result.precision == "rounds"

      assert [
               %{
                 round: 1,
                 ghost_at_ms: 100_000,
                 at_ms: 90_000,
                 delta_ms: -10_000,
                 section_name: "AMRAP 10"
               },
               %{round: 2, ghost_lap_ms: 100_000, lap_ms: 120_000, delta_ms: 10_000},
               %{section_ordinal: 1, section_name: "EMOM", at_ms: nil, delta_ms: nil}
             ] = result.checkpoints

      assert [
               %{section_ordinal: 0, ghost_ms: 600_000, current_ms: 595_000, delta_ms: -5_000},
               %{section_ordinal: 1, ghost_ms: 180_000, current_ms: nil, delta_ms: nil}
             ] = result.sections

      # Not finished yet: no total comparison.
      assert result.total_delta_ms == nil
      assert Pacer.compare(ghost, %{current | completed?: true}, %{}).total_delta_ms == -185_000
    end

    test "precision falls back to sections, then to the finish" do
      assert Pacer.precision([], %{0 => 1}) == "sections"
      assert Pacer.precision([], %{}) == "finish"
      assert Pacer.precision(Pacer.checkpoints([split(0, 0, 5)]), %{}) == "segments"
    end
  end

  defp split(ordinal, round, at) do
    %{
      section_ordinal: ordinal,
      phase: "work",
      round: round,
      elapsed_ms: at,
      segment_index: ordinal
    }
  end
end
