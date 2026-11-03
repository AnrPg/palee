defmodule Palee.Workouts.Domain.LoggedWorkoutChangeTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.LoggedWorkoutChange

  defp result(user, id, hash, at),
    do: %{user_id: user, holder: :training_log, holder_id: id, content_hash: hash, at: at}

  describe "recipients/3 (ADR-393)" do
    test "people whose result reads differently now, one each, about their latest, never the editor" do
      performed = [
        result("ana", "a1", "old", ~U[2026-11-01 08:00:00Z]),
        result("ana", "a2", "old", ~U[2026-11-02 08:00:00Z]),
        %{result("bo", "b1", "older", nil) | holder: :execution},
        result("same", "s1", "new", ~U[2026-11-02 08:00:00Z]),
        result("coach", "c1", "old", ~U[2026-11-02 08:00:00Z])
      ]

      assert [%{user_id: "ana", holder_id: "a2"}, %{user_id: "bo", holder: :execution}] =
               LoggedWorkoutChange.recipients(performed, "new", "coach")
    end

    test "a dated result beats one without a date; nothing changed means nobody" do
      performed = [
        result("ana", "a1", "old", nil),
        result("ana", "a2", "old", ~U[2026-11-02 08:00:00Z])
      ]

      assert [%{holder_id: "a2"}] = LoggedWorkoutChange.recipients(performed, "new", nil)
      assert LoggedWorkoutChange.recipients(performed, "old", nil) == []
      assert LoggedWorkoutChange.recipients([], "new", nil) == []
      assert LoggedWorkoutChange.recipients(performed, nil, nil) == []
    end
  end

  test "one notice per person, WOD and content; the link opens the Journal entry" do
    assert LoggedWorkoutChange.dedupe_key("w1", "abc") == "logged_workout_changed:w1:abc"
    assert LoggedWorkoutChange.journal_url("e1") == "/journal?entry=e1"
  end
end
