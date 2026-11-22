defmodule Palee.Anatomy.DomainTest do
  use ExUnit.Case, async: true

  alias Palee.Anatomy.Domain.{
    ExerciseTargets,
    FitnessQualities,
    GoalSet,
    GoalSuggestion,
    MuscleTaxonomy
  }

  alias Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  describe "MuscleTaxonomy" do
    test "ids are unique and every node's parent exists" do
      ids = Enum.map(MuscleTaxonomy.nodes(), & &1.id)
      assert ids == Enum.uniq(ids)

      for %{parent_id: parent} <- MuscleTaxonomy.nodes(), parent do
        assert MuscleTaxonomy.known?(parent)
      end
    end

    test "every TA2 mesh id belongs to exactly one group" do
      ta2 = MuscleTaxonomy.groups() |> Enum.flat_map(& &1.ta2_ids)
      assert ta2 == Enum.uniq(ta2)
      assert Enum.all?(ta2, &(&1 =~ ~r/^\d+$/))
    end

    test "muscle heads ANR asked for are distinct nodes" do
      for id <- ~w(deltoid-anterior deltoid-lateral deltoid-posterior trapezius-upper
                   trapezius-middle trapezius-lower biceps-brachii-long triceps-brachii-lateral
                   rectus-femoris vastus-medialis biceps-femoris-long gastrocnemius-medial) do
        assert %{kind: :head} = MuscleTaxonomy.fetch(id)
      end
    end

    test "taxonomy v2 adds finer muscles without changing a v1 node (ADR-731)" do
      assert MuscleTaxonomy.version() == 2

      for {id, group} <- [
            {"flexor-digitorum-superficialis", "forearm-flexors"},
            {"piriformis", "hip-rotators"},
            {"rhomboid-major", "rhomboids"},
            {"tibialis-posterior", "deep-calf"},
            {"plantaris", "calves"},
            {"levator-ani", "pelvic-floor"},
            {"big-toe-muscles", "foot-muscles"}
          ] do
        assert %{kind: :head, group_id: ^group} = MuscleTaxonomy.fetch(id)
      end

      assert %{kind: :region} = MuscleTaxonomy.fetch("feet")
      assert length(MuscleTaxonomy.nodes()) <= GoalSet.max_muscles()
      # A group that gained heads draws them (its own meshes moved to them).
      assert Enum.sort(MuscleTaxonomy.fetch("rhomboids").ta2_ids) == ["2232", "2233"]
    end

    test "group_of and heads_of roll heads up to groups" do
      assert MuscleTaxonomy.group_of("deltoid-lateral") == "deltoid"
      assert MuscleTaxonomy.group_of("latissimus-dorsi") == "latissimus-dorsi"
      assert MuscleTaxonomy.group_of("shoulders") == nil
      assert MuscleTaxonomy.heads_of("latissimus-dorsi") == ["latissimus-dorsi"]
      assert "deltoid-anterior" in MuscleTaxonomy.heads_of("deltoid")
    end
  end

  describe "ExerciseTargets" do
    test "every catalog exercise has a curated decision and no stale ids remain" do
      catalog_ids = ExerciseCatalog.entries() |> Enum.map(& &1.id) |> MapSet.new()
      target_ids = MapSet.new(ExerciseTargets.ids())

      assert MapSet.difference(catalog_ids, target_ids) |> MapSet.to_list() == []
      assert MapSet.difference(target_ids, catalog_ids) |> MapSet.to_list() == []
    end

    test "every target names a targetable muscle and a known quality" do
      for id <- ExerciseTargets.ids() do
        %{muscles: muscles, qualities: qualities} = ExerciseTargets.fetch(id)
        assert Enum.all?(muscles, &MuscleTaxonomy.targetable?(&1.id)), id
        assert Enum.all?(qualities, &FitnessQualities.known?/1), id
        assert qualities != [], id
      end
    end

    test "the coach's obvious muscles are there in the right role (ADR-731)" do
      roles = fn id ->
        %{muscles: muscles} = ExerciseTargets.fetch(id)
        Map.new(muscles, &{&1.id, &1.role})
      end

      assert roles.("hip-thrust")["hamstrings"] == :primary
      assert roles.("thruster")["triceps-brachii"] == :primary
      assert roles.("back-squat")["erector-spinae"] == :secondary
      assert roles.("deadlift")["erector-spinae"] == :primary
      assert roles.("pull-up")["forearm-flexors"] == :secondary
      assert roles.("run")["foot-muscles"] == :secondary
    end

    test "a muscle listed twice keeps the strongest role" do
      %{muscles: muscles} = ExerciseTargets.fetch("back-squat")
      assert %{id: "quadriceps", role: :primary} in muscles
      assert hd(muscles).role == :primary
    end
  end

  describe "GoalSuggestion" do
    test "a thruster + pull-up couplet suggests movers and drops covered heads" do
      %{muscles: muscles, qualities: qualities, matched_exercises: 2} =
        GoalSuggestion.suggest([
          %{exercise_ref: "thruster", weight: 3},
          %{exercise_ref: "pull-up", weight: 3}
        ])

      roles = Map.new(muscles, &{&1.id, &1.role})
      assert roles["quadriceps"] == :primary
      assert roles["latissimus-dorsi"] == :primary
      assert roles["deltoid-anterior"] == :primary
      refute Map.has_key?(roles, "shoulders")
      assert "stamina" in qualities
      assert length(qualities) <= 5
    end

    test "unknown exercises are counted, not guessed" do
      assert %{muscles: [], qualities: [], unmatched_exercises: 1} =
               GoalSuggestion.suggest([%{exercise_ref: nil}])
    end

    test "every stabilizer is kept, however small its share (ADR-731)" do
      exercises = [%{exercise_ref: "run", weight: 10}, %{exercise_ref: "farmer-carry", weight: 1}]
      %{muscles: muscles} = GoalSuggestion.suggest(exercises)
      roles = Map.new(muscles, &{&1.id, &1.role})
      assert roles["quadratus-lumborum"] == :secondary
      assert roles["pelvic-floor"] == :stabilizer
    end

    test "a group already in the goals hides its heads of an equal or weaker role" do
      %{muscles: muscles} =
        GoalSuggestion.suggest([
          %{exercise_ref: "back-squat"},
          %{exercise_ref: "calf-raise"}
        ])

      ids = Enum.map(muscles, & &1.id)
      assert "calves" in ids
      refute "soleus" in ids
      refute "gastrocnemius-medial" in ids
    end
  end

  describe "GoalSet" do
    test "normalises goals, keeping the strongest duplicate role" do
      assert {:ok, %{muscles: muscles, qualities: ["stamina", "power"], stimulus: "γρήγορο"}} =
               GoalSet.normalize_goals(%{
                 "muscles" => [
                   %{"id" => "glutes", "role" => "secondary"},
                   %{"id" => "glutes", "role" => "primary"},
                   %{"id" => "core", "role" => "primary"} |> Map.put("id", "rectus-abdominis")
                 ],
                 "qualities" => ["power", "stamina"],
                 "stimulus" => "  γρήγορο "
               })

      assert %{id: "glutes", role: :primary} in muscles
    end

    test "rejects regions, unknown ids, bad roles and long stimulus" do
      assert {:error, {:invalid_goals, _}} =
               GoalSet.normalize_goals(%{muscles: [%{id: "shoulders", role: "primary"}]})

      assert {:error, {:invalid_goals, _}} =
               GoalSet.normalize_goals(%{muscles: [%{id: "deltoid", role: "hero"}]})

      assert {:error, {:invalid_goals, _}} = GoalSet.normalize_goals(%{qualities: ["luck"]})

      assert {:error, {:invalid_goals, _}} =
               GoalSet.normalize_goals(%{stimulus: String.duplicate("α", 281)})
    end

    test "normalises felt feedback" do
      assert {:ok, %{felt_muscles: ["deltoid", "quadriceps"], felt_qualities: ["stamina"]}} =
               GoalSet.normalize_feedback(%{
                 felt_muscles: ["quadriceps", "deltoid", "deltoid"],
                 felt_qualities: ["stamina"]
               })

      assert {:error, _} = GoalSet.normalize_feedback(%{felt_muscles: ["arms"]})
    end
  end
end
