defmodule Palee.Catalog.ReferenceTest do
  @moduledoc """
  ADR-560: the reference tables hold exactly what the code held before the
  move (the seed file), the copy is built from one consistent read, and
  every write to the tables bumps the revision other pods poll.
  """

  use Palee.DataCase, async: false

  alias Palee.Catalog
  alias Palee.Catalog.Domain.Reference
  alias Palee.Catalog.ReferenceStore

  setup do
    reference = Catalog.reference()
    on_exit(fn -> Catalog.put(reference) end)
    :ok
  end

  defp from_db do
    {:ok, rows} = ReferenceStore.load()
    Reference.build(rows, &Palee.Workouts.Domain.WorkoutDsl.ExerciseCatalog.capabilities_for/1)
  end

  test "the migrated tables equal the seed the code held" do
    db = from_db()
    seed = Catalog.seed()

    assert db.taxonomy_version == seed.taxonomy_version
    assert db.nodes == seed.nodes
    assert db.qualities == seed.qualities
    assert length(db.exercises) == 123
    builtin = Enum.filter(db.exercises, &(&1.origin == "builtin"))
    assert builtin == seed.exercises
    assert db.targets == seed.targets
    assert db.search_aliases == seed.search_aliases
  end

  test "every built-in exercise has targets and every target is a group or head" do
    db = from_db()
    assert Enum.all?(db.exercises, &(Reference.targets(db, &1.id) != nil))

    for {_id, %{muscles: muscles}} <- db.targets, %{id: id} <- muscles do
      assert %{kind: kind} = Reference.fetch_node(db, id)
      assert kind in [:group, :head]
    end
  end

  test "a group's meshes include its heads', a region's its groups'" do
    db = from_db()
    deltoid = Reference.fetch_node(db, "deltoid")
    assert Enum.sort(deltoid.ta2_ids) == ["2453", "2454", "2455"]

    assert %{kind: :head, group_id: "deltoid", region_id: "shoulders"} =
             Reference.fetch_node(db, "deltoid-lateral")

    assert "2453" in Reference.fetch_node(db, "shoulders").ta2_ids
  end

  test "labels resolve before aliases; aliases equal to a label are not stored twice" do
    db = from_db()
    assert {:ok, %{id: "romanian-deadlift"}, :alias} = Reference.resolve(db, "rdl")
    assert {:ok, %{id: "muscle-up"}, :canonical} = Reference.resolve(db, "Muscle Up")
    assert {:error, :not_found} = Reference.resolve(db, "DL")
    assert "DL" in Reference.search_aliases(db, "deadlift")
  end

  test "the database refuses a stabilizer on a region and an unknown role" do
    assert_raise Postgrex.Error, ~r/exercise_muscle_targets_(kind_check|muscle_fkey)/, fn ->
      Repo.query!(
        "INSERT INTO exercise_muscle_targets VALUES ('deadlift', 'shoulders', 'region', 'stabilizer')"
      )
    end

    assert_raise Postgrex.Error, ~r/exercise_muscle_targets_role_check/, fn ->
      Repo.query!(
        "UPDATE exercise_muscle_targets SET role = 'main' WHERE exercise_id = 'deadlift'"
      )
    end
  end

  test "a write bumps the revision and refresh_if_stale reloads" do
    {:ok, before} = ReferenceStore.revision()
    Catalog.refresh()
    assert :unchanged = Catalog.refresh_if_stale()

    Repo.query!("UPDATE exercises SET label = 'Conventional Deadlift X' WHERE id = 'deadlift'")
    {:ok, later} = ReferenceStore.revision()
    assert later == before + 1

    assert :refreshed = Catalog.refresh_if_stale()

    assert %{label: "Conventional Deadlift X"} =
             Catalog.reference() |> Reference.fetch_exercise("deadlift")
  end
end
