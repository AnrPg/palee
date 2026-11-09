defmodule Palee.Workouts.ExerciseCatalogStore do
  @moduledoc "Facade over the exercise catalog store adapter (ADR-461)."

  @behaviour Palee.Workouts.Ports.ExerciseCatalogStore

  defp adapter, do: Application.fetch_env!(:palee, :exercise_catalog_store)

  @impl true
  def note_candidates(entries, now), do: adapter().note_candidates(entries, now)
  @impl true
  def list_candidates(status, min_owners, limit),
    do: adapter().list_candidates(status, min_owners, limit)

  @impl true
  def get_candidate(id), do: adapter().get_candidate(id)
  @impl true
  def record_decision(candidate_id, decision, actor_user_id, metadata, now),
    do: adapter().record_decision(candidate_id, decision, actor_user_id, metadata, now)

  @impl true
  def replace_exercise_targets(exercise_id, targets, actor_user_id, now),
    do: adapter().replace_exercise_targets(exercise_id, targets, actor_user_id, now)

  @impl true
  def audit_events(limit), do: adapter().audit_events(limit)
end
