defmodule Palee.Workouts.WorkoutKindStore do
  @moduledoc """
  Facade over the configured `Workouts.Ports.WorkoutKindStore` adapter
  (ADR-690). Box reads and writes open the tenant's session here; the Palee
  team's queue is platform data and opens none.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :workout_kind_store)

  defp within_tenant(context, fun), do: RepoContext.run(context, fun)

  def catalogue(context), do: within_tenant(context, fn -> adapter().catalogue() end)
  def additions, do: adapter().additions()
  def list_box_kinds(context), do: within_tenant(context, fn -> adapter().list_box_kinds() end)
  def get_box_kind(context, id), do: within_tenant(context, fn -> adapter().get_box_kind(id) end)

  def find_box_kind_by_folded(context, folded),
    do: within_tenant(context, fn -> adapter().find_box_kind_by_folded(folded) end)

  def insert_box_kind(context, attrs),
    do: within_tenant(context, fn -> adapter().insert_box_kind(attrs) end)

  def update_box_kind(context, id, changes),
    do: within_tenant(context, fn -> adapter().update_box_kind(id, changes) end)

  def merge_box_kind(context, id, target_ref),
    do: within_tenant(context, fn -> adapter().merge_box_kind(id, target_ref) end)

  def refresh_box_kind(context, id),
    do: within_tenant(context, fn -> adapter().refresh_box_kind(id) end)

  def box_kinds_by_ids(ids), do: adapter().box_kinds_by_ids(ids)

  def box_kinds_with_folded(context, folded),
    do: within_tenant(context, fn -> adapter().box_kinds_with_folded(folded) end)

  def note_box_kind_candidate(kind, organization_id, now),
    do: adapter().note_box_kind_candidate(kind, organization_id, now)

  def note_profile_suggestion(name, folded, suggestion_id, now),
    do: adapter().note_profile_suggestion(name, folded, suggestion_id, now)

  def list_candidates(status, limit), do: adapter().list_candidates(status, limit)
  def recently_decided(limit), do: adapter().recently_decided(limit)
  def get_candidate(id), do: adapter().get_candidate(id)

  def record_decision(candidate_id, status, decision, addition, actor_user_id, now),
    do: adapter().record_decision(candidate_id, status, decision, addition, actor_user_id, now)

  def undigested_candidates, do: adapter().undigested_candidates()
  def mark_digested(ids, now), do: adapter().mark_digested(ids, now)
end
