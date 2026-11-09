defmodule Palee.Community.FollowSuggestions do
  @moduledoc """
  The Community context's public API for «Ίσως γνωρίζεις» (ADR-561): the
  ranking rules (`FollowSuggestionPolicy`) and the suggestions store
  (viewer evidence, candidates, dismissals and the anonymous counters).
  """

  alias Palee.Community.Domain.FollowSuggestionPolicy
  alias Palee.Community.FollowSuggestionStore

  # The engine.
  defdelegate rank(input), to: FollowSuggestionPolicy
  defdelegate learned_factors(rows), to: FollowSuggestionPolicy
  defdelegate recent_since(now), to: FollowSuggestionPolicy
  defdelegate learning_since(now), to: FollowSuggestionPolicy
  defdelegate reasons(), to: FollowSuggestionPolicy

  # The store.
  defdelegate viewer(context), to: FollowSuggestionStore
  defdelegate candidates(context, seed, pool, recent_since), to: FollowSuggestionStore
  defdelegate dismiss(context, user_id, target_id, now), to: FollowSuggestionStore
  defdelegate undismiss(context, user_id, target_id), to: FollowSuggestionStore
  defdelegate count(context, reason, event, n), to: FollowSuggestionStore
  defdelegate rates(context, since), to: FollowSuggestionStore
end
