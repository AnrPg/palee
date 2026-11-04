defmodule Palee.Execution.Domain.TrainingLogSourcePolicyTest do
  @moduledoc "ADR-451: which «Καταγραφή προπόνησης» chips a person gets."
  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.TrainingLogSourcePolicy, as: Policy

  test "freeform is always available and always last" do
    assert Policy.available(%{}) == ["freeform"]

    everything = %{
      box?: true,
      class_package?: true,
      programming_grant?: true,
      library_access?: true,
      library_published?: true
    }

    assert Policy.available(everything) ==
             ["class", "assigned_workout", "library_workout", "freeform"]
  end

  describe "class (Τμήμα)" do
    test "a box member whose package covers classes" do
      assert Policy.allowed?("class", %{box?: true, class_package?: true})
    end

    test "never from a package outside a box (a solo coach's club)" do
      refute Policy.allowed?("class", %{box?: false, class_package?: true})
    end

    test "anyone with a class left to log, whatever the package or club" do
      assert Policy.allowed?("class", %{box?: false, classes_to_log?: true})
      assert Policy.allowed?("class", %{box?: true, class_package?: false, classes_to_log?: true})
    end

    test "not for a box member whose package has no classes and nothing to log" do
      refute Policy.allowed?("class", %{box?: true, class_package?: false})
    end
  end

  describe "assigned workout" do
    test "a package with online programming or personal training" do
      assert Policy.allowed?("assigned_workout", %{programming_grant?: true})
    end

    test "an assignment still to log after the grant ended" do
      assert Policy.allowed?("assigned_workout", %{assignments_to_log?: true})
    end

    test "not without a coach or trainer" do
      refute Policy.allowed?("assigned_workout", %{programming_grant?: false})
    end
  end

  describe "library" do
    test "needs both access and a published workout" do
      assert Policy.allowed?("library_workout", %{library_access?: true, library_published?: true})

      refute Policy.allowed?("library_workout", %{
               library_access?: true,
               library_published?: false
             })

      refute Policy.allowed?("library_workout", %{
               library_access?: false,
               library_published?: true
             })
    end

    test "staff by role, members by package, athletes only by explicit grant" do
      for role <- [:owner, :admin, :coach], do: assert(Policy.library_rule(role) == :role)
      assert Policy.library_rule(:member) == :package
      assert Policy.library_rule(:athlete) == :explicit_package

      for role <- [:guest, :front_desk, :accountant, :janitor, nil],
          do: assert(Policy.library_rule(role) == :never)
    end
  end

  test "class rule: members by package, athletes by explicit grant, staff never" do
    assert Policy.class_rule(:member) == :package
    assert Policy.class_rule(:athlete) == :explicit_package

    for role <- [:owner, :admin, :coach, :guest, :front_desk],
        do: assert(Policy.class_rule(role) == :never)
  end

  test "unknown source types are never allowed" do
    refute Policy.allowed?("other", %{box?: true, class_package?: true})
  end
end
