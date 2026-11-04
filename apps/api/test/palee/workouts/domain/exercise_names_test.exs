defmodule Palee.Workouts.Domain.ExerciseNamesTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.{ExerciseCatalogReview, ExerciseNames}
  alias Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  defp slugs(query, docs \\ ExerciseNames.catalog_documents()),
    do: query |> ExerciseNames.rank(docs, 5) |> Enum.map(& &1.catalog_slug)

  test "folds case, Greek and Latin accents and the final sigma" do
    assert ExerciseNames.fold("  Σκουάτ   Πλάτης ") == "σκουατ πλατησ"
    assert ExerciseNames.fold("Développé") == "developpe"
  end

  test "typos, Greek, abbreviations and accents find the catalog entry" do
    assert "back-squat" == hd(slugs("bak sqat"))
    assert "back-squat" in slugs("σκουατ πλατης")
    assert "back-squat" in slugs("Σκουάτ")
    assert "clean-and-jerk" == hd(slugs("C&J"))
    assert "toes-to-bar" == hd(slugs("T2B"))
    assert "deadlift" == hd(slugs("ντεντλιφτ"))
    assert slugs("zzzz qqqq") == []
  end

  test "every search alias belongs to a catalog entry" do
    ids = MapSet.new(ExerciseCatalog.entries(), & &1.id)

    for entry <- ExerciseCatalog.entries(),
        alias_name <- ExerciseCatalog.search_aliases(entry.id),
        do: assert(is_binary(alias_name) and MapSet.member?(ids, entry.id))
  end

  test "entries clean, deduplicate and link names to the catalog" do
    entries =
      ExerciseNames.entries([
        %{"name" => " back   squat "},
        %{name: "BACK SQUAT"},
        %{"name" => ""},
        %{"name" => "My rehab thing", "catalog_slug" => "not-a-slug"},
        %{"name" => "Toes to bar", "exercise_ref" => "toes-to-bar"}
      ])

    assert [
             %{name: "BACK SQUAT", folded: "back squat", catalog_slug: "back-squat"},
             %{name: "My rehab thing", catalog_slug: nil},
             %{name: "Toes to bar", catalog_slug: "toes-to-bar"}
           ] = entries
  end

  test "groups keep the source order and show a name once" do
    hits = %{
      mine: [%{name: "Back Squat", catalog_slug: nil, uses_count: 10}],
      box: [
        %{name: "back squat", catalog_slug: nil, uses_count: 3},
        %{name: "Box Squat", catalog_slug: nil}
      ],
      palee: [%{name: "Back Squat", catalog_slug: "back-squat", category: "strength"}]
    }

    assert [
             %{source: :mine, items: [%{name: "Back Squat", uses_count: 10}]},
             %{source: :box, items: [%{name: "Box Squat"}]}
           ] = ExerciseNames.group(hits, 5)
  end

  test "approved additions join the catalog documents" do
    additions = [
      %{
        kind: "entry",
        catalog_slug: "sandbag-carry",
        label: "Sandbag Carry",
        category: "strength"
      },
      %{kind: "alias", catalog_slug: "back-squat", label: "Σκουάτ με μπάρα", category: nil}
    ]

    docs = ExerciseNames.catalog_documents(additions)
    assert "sandbag-carry" == hd(slugs("sandbag", docs))
    assert "Σκουάτ με μπάρα" in Enum.find(docs, &(&1.catalog_slug == "back-squat")).aliases
    assert ExerciseCatalog.export(additions) |> Enum.any?(&(&1.id == "sandbag-carry"))
  end

  describe "review decisions" do
    @candidate %{status: "pending", name: "Sandbag Carry"}

    test "a new entry needs a category and a free slug" do
      docs = ExerciseNames.catalog_documents()

      assert {:ok, %{action: "approve_entry", addition: %{catalog_slug: "sandbag-carry"}}} =
               ExerciseCatalogReview.decide(
                 @candidate,
                 %{"decision" => "entry", "category" => "strength"},
                 docs
               )

      assert {:error, :invalid_exercise_category} =
               ExerciseCatalogReview.decide(@candidate, %{"decision" => "entry"}, docs)

      assert {:error, :exercise_already_in_catalog} =
               ExerciseCatalogReview.decide(
                 %{@candidate | name: "Back-squat"},
                 %{"decision" => "alias", "catalog_slug" => "front-squat"},
                 docs
               )
    end

    test "an alias joins an existing entry; decided candidates stay decided" do
      docs = ExerciseNames.catalog_documents()

      assert {:ok, %{action: "approve_alias", catalog_slug: "farmer-carry"}} =
               ExerciseCatalogReview.decide(
                 %{@candidate | name: "Βόλτα αγρότη"},
                 %{"decision" => "alias", "catalog_slug" => "farmer-carry"},
                 docs
               )

      assert {:error, :unknown_exercise_catalog_slug} =
               ExerciseCatalogReview.decide(
                 @candidate,
                 %{"decision" => "alias", "catalog_slug" => "nope"},
                 docs
               )

      assert {:error, :exercise_candidate_already_decided} =
               ExerciseCatalogReview.decide(
                 %{@candidate | status: "rejected"},
                 %{"decision" => "reject"},
                 docs
               )
    end
  end
end
