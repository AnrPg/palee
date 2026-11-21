defmodule Palee.Repo.Migrations.WorkoutGoalsSuggestionBasis do
  @moduledoc """
  ADR-671: `workout_goals.suggestion_basis` is the live suggestion
  (`%{"muscles" => [%{"id", "role"}], "qualities" => [id]}`) that goals the
  coach edited were last reconciled with: set on every staff save of the
  goals and every time new exercises grow them. Publishing (and the
  pre-publish exercise check) adds to edited goals only what the suggestion
  gained since this basis, so a muscle the coach removed is never put back.
  Null for goals saved before ADR-671: the published text's suggestion
  stands in for it once.
  """

  use Ecto.Migration

  def change do
    alter table(:workout_goals) do
      add(:suggestion_basis, :map)
    end
  end
end
