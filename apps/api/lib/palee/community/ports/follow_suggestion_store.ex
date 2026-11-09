defmodule Palee.Community.Ports.FollowSuggestionStore do
  @moduledoc """
  Persistence port for «Ίσως γνωρίζεις» (ADR-561): the viewer's evidence,
  the candidate people and their facts, the viewer's dismissals and the
  anonymous per-reason counters the engine learns from. Every call is bound
  to the session's account.
  """

  @type context :: map()
  @type id :: binary()

  @callback viewer(context()) :: map()
  @doc "Candidates and their facts; `seed` adds the follows of one person the viewer may see."
  @callback candidates(context(), id() | nil, pos_integer(), DateTime.t()) :: [map()]
  @callback dismiss(context(), id(), id(), DateTime.t()) :: :ok
  @callback undismiss(context(), id(), id()) :: :ok
  @callback count(context(), String.t(), String.t(), pos_integer()) :: :ok
  @callback rates(context(), Date.t()) :: [
              %{reason: String.t(), event: String.t(), count: non_neg_integer()}
            ]
end
