defmodule Palee.Workouts.Domain.ExerciseMatcherTest do
  @moduledoc "ADR-570: optimistic, typo-tolerant matching of catalog exercises in free text."
  use ExUnit.Case, async: true

  alias Palee.Anatomy.Domain.GoalSuggestion
  alias Palee.Workouts.Domain.{ExerciseMatcher, FreeTextDocument, FreeTextExercises}
  alias Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  setup_all do
    %{names: ExerciseMatcher.names(ExerciseCatalog.entries(), &ExerciseCatalog.search_aliases/1)}
  end

  defp found(line, names),
    do:
      line |> ExerciseMatcher.match_line(names) |> Enum.map(&{&1.typed, &1.exercise_ref, &1.kind})

  test "exact names, plurals, aliases and Greek names", %{names: names} do
    assert [{"Thrusters", "thruster", :exact}] = found("Thrusters (43/30 kg)", names)
    assert [{"Pullups", "pull-up", :exact}] = found("Pullups", names)
    assert [{"Back squat", "back-squat", :exact}] = found("Back squat 5x5 @80%", names)

    assert [{"KBS", "kettlebell-swing", :exact}, {"box jumps", "box-jump", :exact}] =
             found("KBS 20 / box jumps 15", names)

    assert [{"Κάμψεις", "push-up", :exact}, {"βυθίσεις", "dip", :exact}] =
             found("Κάμψεις και βυθίσεις", names)
  end

  test "typos: swapped, missing and extra letters, split words, transliteration", %{names: names} do
    assert [{"thrsuters", "thruster", :fuzzy}] = found("thrsuters", names)
    assert [{"dubel unders", "double-under", :fuzzy}] = found("dubel unders x50", names)
    assert [{"burpess", "burpee", :fuzzy}] = found("10 burpess", names)
    assert [{"θραστερ", "thruster", _}] = found("θραστερ", names)
    assert [{"Σχοινάκι διπλό", "double-under", :fuzzy}] = found("Σχοινάκι διπλό", names)
  end

  test "noise, numbers, brackets and unknown words match nothing", %{names: names} do
    assert [] = found("21-15-9", names)
    assert [] = found("rest 2 min", names)
    assert [] = found("Sandbag γύρω από το κτίριο", names)
    assert [] = found("(scale: ring rows)", names)
  end

  test "offsets point at the written words and linked spans are skipped", %{names: names} do
    line = "3 rounds: Thrusters, then pull ups"
    [thruster, pull_up] = ExerciseMatcher.match_line(line, names)
    assert String.slice(line, thruster.from, thruster.to - thruster.from) == "Thrusters"
    assert String.slice(line, pull_up.from, pull_up.to - pull_up.from) == "pull ups"

    skip = fn {from, _to} -> from == thruster.from end
    assert [%{exercise_ref: "pull-up"}] = ExerciseMatcher.match_line(line, names, skip)
  end

  test "a document's lines carry links; rejected words count as nothing" do
    document = %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "21-15-9"}]},
        %{
          "type" => "paragraph",
          "content" => [
            %{
              "type" => "text",
              "text" => "Thrusterz",
              "marks" => [%{"type" => "exerciseLink", "attrs" => %{"ref" => "thruster"}}]
            },
            %{"type" => "text", "text" => " and wall balls"}
          ]
        },
        %{
          "type" => "bulletList",
          "content" => [
            %{
              "type" => "listItem",
              "content" => [
                %{
                  "type" => "paragraph",
                  "content" => [
                    %{
                      "type" => "text",
                      "text" => "Run",
                      "marks" => [%{"type" => "exerciseLink", "attrs" => %{"ref" => nil}}]
                    },
                    %{"type" => "hardBreak"},
                    %{"type" => "text", "text" => "run again"}
                  ]
                }
              ]
            }
          ]
        },
        %{"type" => "paragraph"}
      ]
    }

    [first, second, third, empty] = FreeTextDocument.lines(document)
    assert first.text == "21-15-9" and first.links == []
    assert [%{from: 0, to: 9, ref: "thruster"}] = second.links
    assert third.text == "Run\nrun again"
    assert [%{text: "Run", ref: nil}] = third.links
    assert empty.text == ""

    refs =
      document
      |> FreeTextDocument.lines()
      |> FreeTextExercises.from_lines()
      |> Enum.map(& &1.exercise_ref)

    assert refs == ["thruster", "wall-ball"]
  end

  test "edited goals only grow: added muscles and promoted roles, never demoted" do
    current = %{
      muscles: [%{id: "quadriceps", role: "primary"}, %{id: "deltoid", role: "stabilizer"}],
      qualities: ["stamina"]
    }

    suggested = %{
      muscles: [
        %{id: "quadriceps", role: :secondary},
        %{id: "deltoid", role: :secondary},
        %{id: "latissimus-dorsi", role: :primary},
        %{id: "deltoid-anterior", role: :stabilizer}
      ],
      qualities: ["power"]
    }

    assert %{muscles: muscles, qualities: ["stamina", "power"]} =
             GoalSuggestion.merge_up(current, suggested)

    assert Enum.sort(muscles) ==
             Enum.sort([
               %{id: "quadriceps", role: "primary"},
               %{id: "latissimus-dorsi", role: "primary"},
               %{id: "deltoid", role: "secondary"}
             ])
  end
end
