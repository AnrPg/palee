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

    assert profile.algorithm == %{id: "fitness-profile", version: 2}
    refute profile.neutral_standards

    strength = Enum.find(profile.domains, &(&1.domain == "strength"))
    assert %{score: score, confidence: "medium", reasons: reasons} = strength
    assert score == 48

    assert %{benchmark: "deadlift", estimated: true, value: value} =
             Enum.find(reasons, &(&1.benchmark == "deadlift"))

    assert value == 116.5

    assert %{score: 43, confidence: "low"} = Enum.find(profile.domains, &(&1.domain == "metcon"))
    assert %{score: 20} = Enum.find(profile.domains, &(&1.domain == "gymnastics"))
    assert %{score: nil, reasons: []} = Enum.find(profile.domains, &(&1.domain == "power"))

    # (48 + 42.5 + 20) / 3
    assert %{score: 37, domains_scored: 3} = profile.overall

    assert [%{domain: "gymnastics", kind: "weakest_domain", gap: 26} | rest] = profile.focus
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
    # (89.3 × 0.5 + 39.1 × 1) / 1.5
    assert strength.score == 56
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

  describe "ADR-395 version 2" do
    test "a lift reads as a multiple of body weight, and says what the next level takes" do
      squat = pr("Back squat", "kg", 70, metrics: %{"reps" => 3})

      with_weight =
        FitnessProfile.build(%{
          prs: [squat],
          today: @today,
          division: "women",
          body_weight_kg: 60
        })

      [reason] = Enum.find(with_weight.domains, &(&1.domain == "strength")).reasons

      assert %{
               basis: "body_weight",
               value: 77.0,
               load: 70.0,
               reps: 3,
               ratio: 1.28,
               body_weight_kg: 60.0,
               points: 55.2,
               next: %{points: 75, value: 96.0}
             } = reason

      assert with_weight.inputs.body_weight_kg == 60.0

      without =
        FitnessProfile.build(%{prs: [squat], today: @today, division: "women"})

      [absolute] = Enum.find(without.domains, &(&1.domain == "strength")).reasons

      assert %{basis: "absolute", ratio: nil, points: 52.0, next: %{points: 75, value: 100.0}} =
               absolute
    end

    test "body weight leaves reps and times alone; a time's next level is a lower time" do
      profile =
        FitnessProfile.build(%{
          prs: [pr("Pull ups", "reps", 10), pr("Fran", "mins_secs", 360)],
          today: @today,
          division: "women",
          body_weight_kg: 60
        })

      [pull_ups] = Enum.find(profile.domains, &(&1.domain == "gymnastics")).reasons
      assert %{basis: "absolute", next: %{points: 75, value: 15}} = pull_ups

      [fran] = Enum.find(profile.domains, &(&1.domain == "metcon")).reasons
      assert %{next: %{points: 75, value: 255}} = fran
    end

    test "an age band from 35 eases every target by its percentage" do
      assert FitnessBenchmarks.age_ready?()
      assert FitnessBenchmarks.age_band(34) == nil
      assert FitnessBenchmarks.age_band(41) == "40_44"
      assert FitnessBenchmarks.age_band(63) == "60_plus"
      assert FitnessBenchmarks.age_factor("40_44", "women") == 8
      assert FitnessBenchmarks.age_factor("40_44", "men") == 10
      # Without a division, the mean of the two.
      assert FitnessBenchmarks.age_factor("40_44", nil) == 9.0

      profile =
        FitnessProfile.build(%{
          prs: [pr("Fran", "mins_secs", 360)],
          today: @today,
          division: "women",
          age: 41
        })

      # Fran's 75 target 4:15 becomes 4:15 × 1.08 ≈ 4:35 for a woman of 41.
      [fran] = Enum.find(profile.domains, &(&1.domain == "metcon")).reasons
      assert %{age_band: "40_44", age_percent: 8, points: 56.3, next: %{value: 275}} = fran
      assert profile.inputs.age_ready

      young =
        FitnessProfile.build(%{
          prs: [pr("Fran", "mins_secs", 360)],
          today: @today,
          division: "women",
          age: 30
        })

      [fran] = Enum.find(young.domains, &(&1.domain == "metcon")).reasons
      assert %{age_band: nil, age_percent: nil, points: 50.0} = fran
    end

    test "the PRs as they stood on a date come from the PR history" do
      squat = %{
        id: "pr-1",
        name: "Back squat",
        unit: "kg",
        current_score: Decimal.new("100"),
        beaten_on: ~D[2026-10-01],
        supporting_metrics: %{}
      }

      history = [
        %{
          pr_record_id: "pr-1",
          score: Decimal.new("80"),
          beaten_on: ~D[2026-06-01],
          supporting_metrics: %{}
        },
        %{
          pr_record_id: "pr-1",
          score: Decimal.new("90"),
          beaten_on: ~D[2026-08-15],
          supporting_metrics: %{}
        }
      ]

      assert [%{current_score: score, beaten_on: ~D[2026-06-01]}] =
               FitnessProfile.as_of([squat], history, ~D[2026-08-01])

      assert Decimal.equal?(score, 80)
      assert FitnessProfile.as_of([squat], history, ~D[2026-05-01]) == []

      assert [%{beaten_on: ~D[2026-10-01]}] =
               FitnessProfile.as_of([squat], history, ~D[2026-10-31])
    end

    test "with_change says how each domain moved since the earlier profile" do
      now =
        FitnessProfile.build(%{
          prs: [pr("Back squat", "kg", 140), pr("Fran", "mins_secs", 360)],
          today: @today,
          division: "men"
        })

      before =
        FitnessProfile.build(%{
          prs: [pr("Back squat", "kg", 120), pr("Fran", "mins_secs", 360)],
          today: @today,
          division: "men"
        })

      changed = FitnessProfile.with_change(now, before)
      strength = Enum.find(changed.domains, &(&1.domain == "strength"))
      assert %{score: 64, previous_score: 50, change: 14} = strength
      assert %{change: 0} = Enum.find(changed.domains, &(&1.domain == "metcon"))
      assert %{change: nil} = Enum.find(changed.domains, &(&1.domain == "power"))
      assert changed.overall.change == 7
    end

    test "the card shows the strictest of the person's choice and their coaches'" do
      assert FitnessProfile.display("all", []) == %{mode: "all", set_by: "self"}
      assert FitnessProfile.display(nil, []) == %{mode: "all", set_by: "self"}

      assert FitnessProfile.display("all", ["progress_only"]) ==
               %{mode: "progress_only", set_by: "coach"}

      assert FitnessProfile.display("none", ["progress_only"]) == %{mode: "none", set_by: "self"}

      assert FitnessProfile.display("progress_only", ["none", "progress_only"]) ==
               %{mode: "none", set_by: "coach"}
    end

    test "progress only keeps the direction of change, never a score" do
      now = FitnessProfile.build(%{prs: [pr("Back squat", "kg", 140)], today: @today})
      before = FitnessProfile.build(%{prs: [pr("Back squat", "kg", 120)], today: @today})

      shown =
        now |> FitnessProfile.with_change(before) |> FitnessProfile.for_display("progress_only")

      assert shown.overall == nil

      assert %{tested: true, direction: "up"} =
               strength = Enum.find(shown.domains, &(&1.domain == "strength"))

      refute Map.has_key?(strength, :score)
      refute Map.has_key?(strength, :reasons)
      assert %{tested: false, direction: nil} = Enum.find(shown.domains, &(&1.domain == "power"))

      hidden = FitnessProfile.for_display(now, "none")
      assert hidden.domains == [] and hidden.focus == [] and hidden.overall == nil
    end

    test "progress only keeps «Τι να δουλέψεις» without the scores behind it" do
      profile =
        FitnessProfile.build(%{
          prs: [pr("Back squat", "kg", 200), pr("Fran", "mins_secs", 600)],
          today: @today,
          division: "men"
        })

      assert %{kind: "weakest_domain", score: _, others_mean: _, gap: _} =
               Enum.find(profile.focus, &(&1.kind == "weakest_domain"))

      shown = FitnessProfile.for_display(profile, "progress_only")
      weakest = Enum.find(shown.focus, &(&1.kind == "weakest_domain"))
      assert weakest == %{domain: "metcon", kind: "weakest_domain"}
    end

    test "the next level is chosen from the exact reading, not the rounded points" do
      # 99.5 kg at 62.2 kg is 1.5997 × body weight: 74.98 points, shown as
      # 75.0, still short of the 75-point anchor (1.60 ×).
      profile =
        FitnessProfile.build(%{
          prs: [pr("Back squat", "kg", 99.5)],
          today: @today,
          division: "women",
          body_weight_kg: 62.2
        })

      [squat] = Enum.find(profile.domains, &(&1.domain == "strength")).reasons
      assert %{points: 75.0, next: %{points: 75, value: 100.0}} = squat
    end

    test "of several history rows on one day, the last one written counts" do
      squat = %{
        id: "pr-1",
        name: "Back squat",
        unit: "kg",
        current_score: Decimal.new("100"),
        beaten_on: ~D[2026-10-01],
        supporting_metrics: %{}
      }

      # Oldest first, as the PR store lists them.
      history =
        for score <- ["80", "85", "90"],
            do: %{
              pr_record_id: "pr-1",
              score: Decimal.new(score),
              beaten_on: ~D[2026-06-01],
              supporting_metrics: %{}
            }

      assert [%{current_score: score}] = FitnessProfile.as_of([squat], history, ~D[2026-08-01])
      assert Decimal.equal?(score, 90)

      # On the PR's own day the PR itself is the latest.
      same_day = %{squat | beaten_on: ~D[2026-06-01]}
      assert [%{current_score: score}] = FitnessProfile.as_of([same_day], history, ~D[2026-06-01])
      assert Decimal.equal?(score, 100)
    end
  end
end
