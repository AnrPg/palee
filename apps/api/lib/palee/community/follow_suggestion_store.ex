defmodule Palee.Community.FollowSuggestionStore do
  @moduledoc """
  Facade over the «Ίσως γνωρίζεις» adapter (ADR-561). Every call runs inside
  the caller's `RepoContext` session, the acting person's personal session.
  """

  @behaviour Palee.Community.Ports.FollowSuggestionStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :community_follow_suggestion_store)

  defp call(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def viewer(context), do: call(context, :viewer, [])

  @impl true
  def candidates(context, seed, pool, recent_since),
    do: call(context, :candidates, [seed, pool, recent_since])

  @impl true
  def dismiss(context, user_id, target_id, now),
    do: call(context, :dismiss, [user_id, target_id, now])

  @impl true
  def undismiss(context, user_id, target_id), do: call(context, :undismiss, [user_id, target_id])

  @impl true
  def count(context, reason, event, n), do: call(context, :count, [reason, event, n])

  @impl true
  def rates(context, since), do: call(context, :rates, [since])
end
