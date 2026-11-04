defmodule Palee.Ranks.Domain.SkillNoticePolicy do
  @moduledoc """
  The calm notice of new skills (ADR-400 follow-up): the ticks a coach made
  for one person within a window are told once, grouped, never one
  notification per tick. A tick undone before the window closes is gone
  (unticking deletes it), so it is never told.
  """

  @doc """
  `checks` are the person's ticks not yet told; `ranks_by_id` the box's
  ranks. `nil` when there is nothing to tell (every tick undone, or its rank
  gone), else `%{count, rank_id, rank_name, ranks}`: the number of new
  skills, the rank most of them belong to (the earliest by position on a
  tie) and how many ranks they span.
  """
  def notice(checks, ranks_by_id) do
    known = Enum.filter(checks, &Map.has_key?(ranks_by_id, &1.rank_id))

    case Enum.group_by(known, & &1.rank_id) do
      groups when map_size(groups) == 0 ->
        nil

      groups ->
        {rank_id, _ticks} =
          Enum.max_by(groups, fn {rank_id, ticks} ->
            {length(ticks), -Map.fetch!(ranks_by_id, rank_id).position}
          end)

        %{
          count: length(known),
          rank_id: rank_id,
          rank_name: Map.fetch!(ranks_by_id, rank_id).name,
          ranks: map_size(groups)
        }
    end
  end
end
