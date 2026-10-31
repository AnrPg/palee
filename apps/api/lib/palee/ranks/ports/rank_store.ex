defmodule Palee.Ranks.Ports.RankStore do
  @moduledoc """
  Persistence port of belts and levels (ADR-377). Every call runs in the
  box's tenant session (row security keeps each box to its own rows).
  """

  alias Palee.Ranks.{RankAward, RankLadder}

  @type id :: Ecto.UUID.t()
  @type result(t) :: {:ok, t} | {:error, term()}

  @callback list_ladders() :: [RankLadder.t()]
  @callback get_ladder(id()) :: RankLadder.t() | nil
  @doc "Creates a ladder with its ranks (`ranks` as cast by `LadderPolicy`)."
  @callback insert_ladder(map(), [map()]) :: result(RankLadder.t())
  @doc "Changes a ladder and replaces its ranks: kept by id, new ones added, missing ones removed (`:rank_in_use` when awarded)."
  @callback update_ladder(RankLadder.t(), map(), [map()]) :: result(RankLadder.t())
  @callback archive_ladder(RankLadder.t(), DateTime.t()) :: result(RankLadder.t())

  @callback list_awards(user_id :: id()) :: [RankAward.t()]
  @callback get_award(id()) :: RankAward.t() | nil
  @callback insert_award(map()) :: result(RankAward.t())
  @callback revoke_award(RankAward.t(), map()) :: result(RankAward.t())
end
