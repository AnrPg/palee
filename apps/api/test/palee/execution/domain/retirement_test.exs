defmodule Palee.Execution.Domain.RetirementTest do
  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.Retirement

  defp amrap(id, seconds, extra \\ %{}) do
    Map.merge(
      %{
        segment_key: "segment:#{id}",
        section_id: id,
        section_name: "AMRAP",
        format: "amrap",
        kind: :countdown,
        phase: "work",
        duration_seconds: seconds,
        scoreable: true,
        score_config: %{"type" => "rounds_reps"}
      },
      extra
    )
  end

  defp for_time(id),
    do: %{
      section_id: id,
      format: "for_time",
      kind: :countup,
      phase: "work",
      duration_seconds: 600,
      scoreable: true,
      score_config: %{"type" => "time"}
    }

  describe "time_set_sections/1" do
    test "keeps countdown and fixed-window sections, drops count-ups and open windows" do
      segments = [
        amrap("a", 720),
        for_time("ft"),
        %{
          section_id: "emom",
          format: "emom",
          kind: :countdown,
          phase: "work",
          duration_seconds: 60
        },
        %{
          section_id: "emom",
          format: "emom",
          kind: :countdown,
          phase: "work",
          duration_seconds: 60
        },
        %{
          section_id: "death",
          format: "death_by",
          kind: :interval_cycle,
          phase: "work",
          duration_seconds: 60
        },
        %{
          section_id: "intervals",
          format: "structured_plan",
          kind: :interval_cycle,
          phase: "work",
          duration_seconds: 40,
          total_rounds: 3,
          timer_config: %{interval_pattern_seconds: [40, 20]}
        },
        %{
          section_id: "rest",
          format: "rest",
          kind: :countdown,
          phase: "rest",
          duration_seconds: 120
        },
        %{
          section_id: "a:rest-after",
          kind: :countdown,
          phase: "rest",
          duration_seconds: 60,
          between_sections: true
        }
      ]

      sections = Retirement.time_set_sections(segments)

      assert Map.keys(sections) |> Enum.sort() == ["a", "emom", "intervals"]
      assert sections["a"].planned_ms == 720_000
      assert sections["emom"].planned_ms == 120_000
      # work 40 + off 20 + work 40
      assert sections["intervals"].planned_ms == 100_000
    end

    test "a section scored only by time is not time-set" do
      segment = amrap("t", 600, %{score_config: %{"metrics" => [%{"kind" => "time"}]}})
      assert Retirement.time_set_sections([segment]) == %{}
    end
  end

  describe "assess/3" do
    test "nil without a time-set section" do
      assert Retirement.assess([for_time("ft")], %{section_elapsed_ms: %{"ft" => 1}}, 3) == nil
    end

    test "stopped_early when the clock ran less than its length" do
      facts =
        Retirement.assess(
          [amrap("a", 900)],
          %{section_elapsed_ms: %{"a" => 540_000}, activity: %{"a" => [60_000, 120_000]}},
          3
        )

      assert facts["verdict"] == "stopped_early"
      assert [%{"stopped_early_ms" => 360_000, "ran_ms" => 540_000}] = facts["sections"]
    end

    test "a section never reached counts as stopped early" do
      facts =
        Retirement.assess(
          [amrap("a", 300), amrap("b", 300)],
          %{section_elapsed_ms: %{"a" => 300_000}},
          3
        )

      verdicts = Map.new(facts["sections"], &{&1["section_id"], &1["verdict"]})
      assert verdicts == %{"a" => "unknown", "b" => "stopped_early"}
      assert facts["verdict"] == "stopped_early"
    end

    test "the clock tolerance absorbs the last tick" do
      facts =
        Retirement.assess(
          [amrap("a", 600)],
          %{
            section_elapsed_ms: %{"a" => 599_400},
            activity: %{"a" => [200_000, 400_000, 590_000]}
          },
          3
        )

      assert facts["verdict"] == "full"
    end

    test "idle when the clock ran on far past the athlete's own pace" do
      # rounds every 60 s, then 6 minutes without a tap
      taps = [60_000, 120_000, 180_000, 240_000]

      facts =
        Retirement.assess(
          [amrap("a", 600)],
          %{section_elapsed_ms: %{"a" => 600_000}, activity: %{"a" => taps}},
          3
        )

      assert [%{"verdict" => "idle", "idle_tail_ms" => 360_000, "median_tap_gap_ms" => 60_000}] =
               facts["sections"]
    end

    test "a tail within the factor is full" do
      taps = [100_000, 200_000, 300_000, 400_000, 500_000]

      facts =
        Retirement.assess(
          [amrap("a", 600)],
          %{section_elapsed_ms: %{"a" => 600_000}, activity: %{"a" => taps}},
          3
        )

      assert facts["verdict"] == "full"
    end

    test "no idle verdict without a factor; facts are still recorded" do
      facts =
        Retirement.assess(
          [amrap("a", 600)],
          %{section_elapsed_ms: %{"a" => 600_000}, activity: %{"a" => [60_000, 120_000]}},
          nil
        )

      assert [%{"verdict" => "full", "idle_tail_ms" => 480_000}] = facts["sections"]
    end

    test "unknown with fewer than two taps" do
      facts =
        Retirement.assess(
          [amrap("a", 600)],
          %{section_elapsed_ms: %{"a" => 600_000}, activity: %{"a" => [5_000]}},
          3
        )

      assert facts["verdict"] == "unknown"
    end

    test "shortened when the athlete took time off the clock and ran the rest" do
      adjustments = %{"segment:a" => %{"delta_seconds" => -120, "section_id" => "a"}}

      facts =
        Retirement.assess(
          [amrap("a", 600)],
          %{section_elapsed_ms: %{"a" => 480_000}, duration_adjustments: adjustments},
          3
        )

      assert [%{"verdict" => "shortened", "adjusted_ms" => 480_000, "stopped_early_ms" => 0}] =
               facts["sections"]
    end
  end

  describe "merge_activity/3" do
    test "keeps time-set sections and valid taps, and only accumulates" do
      segments = [amrap("a", 600), for_time("ft")]

      counters =
        Retirement.merge_activity(
          %{"pauses" => 1},
          %{"a" => [30_000, -1, "x", 10_000], "ft" => [5_000], "ghost" => [1]},
          segments
        )

      assert counters["activity"] == %{"a" => [10_000, 30_000]}
      assert counters["pauses"] == 1

      again = Retirement.merge_activity(counters, %{"a" => [20_000]}, segments)
      assert again["activity"] == %{"a" => [10_000, 20_000, 30_000]}

      assert Retirement.merge_activity(again, nil, segments)["activity"] == again["activity"]
    end

    test "caps the taps kept per section" do
      taps = Enum.map(1..400, &(&1 * 1_000))
      counters = Retirement.merge_activity(%{}, %{"a" => taps}, [amrap("a", 600)])
      assert length(counters["activity"]["a"]) == Retirement.max_taps_per_section()
    end
  end
end
