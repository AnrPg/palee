defmodule Palee.Workouts.GoalStore do
  @moduledoc """
  Facade over the configured WOD-goals adapter
  (`Workouts.Ports.GoalStore`, ADR-163). Every call runs inside a
  `RepoContext` tenant session, so a gym only ever reads and writes its own
  workouts' goals.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :workout_goal_store)

  def get_goals(context, workout_id),
    do: RepoContext.run(context, fn -> adapter().get_goals(workout_id) end)

  def resolve_goals(context, workout_id),
    do: RepoContext.run(context, fn -> adapter().resolve_goals(workout_id) end)

  def put_goals(context, workout_id, attrs),
    do: RepoContext.run(context, fn -> adapter().put_goals(workout_id, attrs) end)

  def match_memories(context, folded),
    do: RepoContext.run(context, fn -> adapter().match_memories(folded) end)

  def update_match_memories(context, remember, forget, decided_by_id, now),
    do:
      RepoContext.run(context, fn ->
        adapter().update_match_memories(remember, forget, decided_by_id, now)
      end)
end
