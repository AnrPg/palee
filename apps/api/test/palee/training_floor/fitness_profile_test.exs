defmodule Palee.Pantheon.Domain.FitnessProfileTest do
  use ExUnit.Case, async: true

  alias Palee.Pantheon.Domain.{FitnessBenchmarks, FitnessProfile}

  @today ~D[2026-10-31]

  defp pr(name, unit, score, opts \\ []) do
    %{
      name: name,
      unit: unit,
      current_score: Decimal.new(to_string(score)),
      beaten_on: Keyword.get(opts, :on, ~D[2026-10-01]),
      supporting_metrics: Keyword.get(opts, :metrics, %{})
    }
  end

  test "benchmarks match English and Greek names, case and accents aside" do
    assert %{key: "back_squat"} = FitnessBenchmarks.match("Back Squat")
    assert %{key: "back_squat"} = FitnessBenchmarks.match("Πίσω κάθισμα")
    assert %{key: "pull_ups"} = FitnessBenchmarks.match("Pull-ups")
    assert %{key: "fran"} = FitnessBenchmarks.match("FRAN")
    assert FitnessBenchmarks.match("Bulgarian split squat") == nil
  end

  test "points interpolate between anchors, falling below and capped above" do
    anchors = [{60, 20}, {100, 50}, {140, 75}, {180, 95}]
    assert FitnessProfile.points(100, anchors, false) == 50.0
    assert FitnessProfile.points(120, anchors, false) == 62.5
    assert FitnessProfile.points(20, anchors, false) == 0.0
    assert FitnessProfile.points(40, anchors, false) == 10.0
    assert FitnessProfile.points(400, anchors, false) == 100.0

    # Times: lower is better.
    times = [{600, 20}, {360, 50}, {240, 75}, {150, 95}]
    assert FitnessProfile.points(360, times, true) == 50.0
    assert FitnessProfile.points(300, times, true) == 62.5
  end

  test "a profile from PRs, with its reasoning, versioned" do
    profile =
      FitnessProfile.build(%{
        prs: [
          pr("Back squat", "kg", 140),
          pr("Deadlift", "kg", 100, metrics: %{"reps" => 5}),
          pr("Fran", "mins_secs", 360),
          pr("Pull ups", "reps", 3),
          pr("Bench press", "reps", 10),
          pr("My own lift", "kg", 50)
        ],
        today: @today,
        division: "men"
      })

    assert profile.algorithm == %{id: "fitness-profile", version: 1}
    refute profile.neutral_standards

    strength = Enum.find(profile.domains, &(&1.domain == "strength"))
    assert %{score: score, confidence: "medium", reasons: reasons} = strength
    assert score == 58

    assert %{benchmark: "deadlift", estimated: true, value: value} =
             Enum.find(reasons, &(&1.benchmark == "deadlift"))

    assert value == 116.5

    assert %{score: 50, confidence: "low"} = Enum.find(profile.domains, &(&1.domain == "metcon"))
    assert %{score: 20} = Enum.find(profile.domains, &(&1.domain == "gymnastics"))
    assert %{score: nil, reasons: []} = Enum.find(profile.domains, &(&1.domain == "power"))

    # (58 + 50 + 20) / 3
    assert %{score: 43, domains_scored: 3} = profile.overall

    assert [%{domain: "gymnastics", kind: "weakest_domain", gap: 34} | rest] = profile.focus
    assert Enum.any?(rest, &(&1.kind == "untested_domain"))
    assert length(profile.focus) <= 3
  end

  test "no overall from one domain; neutral standards without a division" do
    profile = FitnessProfile.build(%{prs: [pr("Back squat", "kg", 100)], today: @today})
    assert profile.neutral_standards
    assert profile.overall == nil
  end

  test "an old PR counts half and flags the domain stale" do
    profile =
      FitnessProfile.build(%{
        prs: [pr("Back squat", "kg", 180, on: ~D[2024-01-01]), pr("Deadlift", "kg", 130)],
        today: @today,
        division: "men"
      })

    strength = Enum.find(profile.domains, &(&1.domain == "strength"))
    # (95 × 0.5 + 50 × 1) / 1.5
    assert strength.score == 65
    refute strength.stale
  end

  test "undertrained qualities are suggested; an injured domain never is" do
    qualities = %{
      sessions: 10,
      qualities: [
        %{id: "strength", score: 1.0},
        %{id: "coordination", score: 0.1},
        %{id: "stamina", score: 0.8}
      ]
    }

    profile =
      FitnessProfile.build(%{
        prs: [pr("Back squat", "kg", 140), pr("Fran", "mins_secs", 240)],
        today: @today,
        division: "men",
        qualities: qualities,
        injured_domains: ["gymnastics"]
      })

    refute Enum.any?(profile.focus, &(&1.domain == "gymnastics"))
    assert profile.injury_caution

    # An active injury of unknown domains: nothing is suggested at all.
    profile =
      FitnessProfile.build(%{prs: [], today: @today, qualities: qualities, active_injury: true})

    assert profile.focus == []
    assert profile.injury_caution

    profile = FitnessProfile.build(%{prs: [], today: @today, qualities: qualities})

    assert Enum.any?(
             profile.focus,
             &match?(
               %{domain: "gymnastics", kind: "undertrained_quality", quality: "coordination"},
               &1
             )
           )
  end
end
