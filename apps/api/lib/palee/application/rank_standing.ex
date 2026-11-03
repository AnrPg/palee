defmodule Palee.Application.RankStanding do
  @moduledoc """
  Where one person stands on each of the box's ladders (ADR-377): current
  rank and stripes, the next rank with progress, and the history. Read in
  the box's tenant session; shared by the coach's and the person's views.
  """

  alias Palee.Application.Clock
  alias Palee.{Ranks, Scheduling}

  @history_limit 2_000

  def call(context, user_id) do
    {ladders, awards} =
      Ranks.with_context(context, fn -> {Ranks.list_ladders(), Ranks.list_awards(user_id)} end)

    history = attendance(context, user_id, ladders)
    today = Clock.today()

    ladders
    |> Enum.map(
      &ladder_standing(&1, Enum.filter(awards, fn a -> a.ladder_id == &1.id end), history, today)
    )
  end

  defp attendance(_context, _user_id, []), do: []

  defp attendance(context, user_id, _ladders) do
    case Scheduling.list_class_history(context, user_id, %{limit: @history_limit}) do
      %{entries: entries} -> entries
      _other -> []
    end
  end

  defp ladder_standing(ladder, awards, history, today) do
    ranks = Enum.sort_by(ladder.ranks, & &1.position)
    by_id = Map.new(ranks, &{&1.id, &1})
    current = Ranks.current_award(awards)
    current_rank = current && Map.get(by_id, current.rank_id)
    next = Ranks.next_rank(ranks, current_rank)
    since = current && current.awarded_on

    %{
      ladder: present_ladder(ladder),
      current:
        current &&
          %{
            award_id: current.id,
            rank: present_rank(current_rank),
            stripes: current.stripes,
            awarded_on: current.awarded_on
          },
      next: next && present_rank(next),
      progress:
        Ranks.progress(
          next,
          since,
          Ranks.count_attended(history, ladder.class_type_ids || [], since),
          today
        ),
      history: Enum.map(awards, &present_award(&1, by_id))
    }
  end

  def present_ladder(ladder) do
    %{
      id: ladder.id,
      name: ladder.name,
      discipline: ladder.discipline,
      family: Ranks.discipline_family(ladder.discipline),
      style: ladder.style,
      class_type_ids: ladder.class_type_ids || [],
      ranks: ladder.ranks |> Enum.sort_by(& &1.position) |> Enum.map(&present_rank/1)
    }
  end

  def present_rank(nil), do: nil

  def present_rank(rank) do
    %{
      id: rank.id,
      position: rank.position,
      name: rank.name,
      color: rank.color,
      max_stripes: rank.max_stripes,
      requirements: rank.requirements || %{},
      scale_level_slug: rank.scale_level_slug
    }
  end

  def present_award(award, ranks_by_id) do
    rank = Map.get(ranks_by_id, award.rank_id)

    %{
      id: award.id,
      ladder_id: award.ladder_id,
      rank_id: award.rank_id,
      rank_name: rank && rank.name,
      color: rank && rank.color,
      stripes: award.stripes,
      awarded_on: award.awarded_on,
      note: award.note,
      skills_checked: award.skills_checked || [],
      certificate_number: award.certificate_number,
      revoked: not is_nil(award.revoked_at),
      revoke_reason: award.revoke_reason
    }
  end
end
