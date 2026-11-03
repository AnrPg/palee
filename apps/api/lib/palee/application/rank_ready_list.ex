defmodule Palee.Application.RankReadyList do
  @moduledoc """
  «Πληροί τις προϋποθέσεις» for the coach (ADR-400 follow-up): the people
  who hold a rank on a ladder and meet what that ladder counts for its next
  rank (days, classes, skills, or a mix, per ladder). A coach sees their
  own clients, staff with full coaching scope everyone (`manage_coaching`,
  ADR-100). Classes are counted for everyone at once
  (`Scheduling.count_attended_since/3`). The promotion stays the coach's.
  """

  alias Palee.Application.{AuthorizeClientAccess, Clock, RankStanding}
  alias Palee.{Identity, Organizations, Ranks, Scheduling}

  def call(context) do
    with {:ok, scope} <- scope(context) do
      {ladders, awards, checks} =
        Ranks.with_context(context, fn ->
          {Ranks.list_ladders(), Ranks.list_awards_for(scope), Ranks.list_skill_checks_for(scope)}
        end)

      today = Clock.today()
      checks_by_user = Enum.group_by(checks, & &1.user_id)

      people =
        ladders
        |> Enum.flat_map(&ready_on(context, &1, awards, checks_by_user, today))
        |> Enum.sort_by(&{&1.nickname || "", &1.ladder.name})

      {:ok, %{people: people}}
    end
  end

  defp ready_on(context, ladder, awards, checks_by_user, today) do
    ranks = Enum.sort_by(ladder.ranks, & &1.position)
    by_id = Map.new(ranks, &{&1.id, &1})

    holders =
      awards
      |> Enum.filter(&(&1.ladder_id == ladder.id))
      |> Enum.group_by(& &1.user_id)
      |> Enum.flat_map(fn {user_id, mine} ->
        case Ranks.current_award(mine) do
          nil -> []
          current -> [{user_id, current, Map.get(by_id, current.rank_id)}]
        end
      end)
      |> Enum.filter(fn {_user_id, _current, rank} -> rank end)

    attended =
      Scheduling.count_attended_since(
        context,
        Map.new(holders, fn {user_id, current, _rank} -> {user_id, current.awarded_on} end),
        ladder.class_type_ids || []
      )

    Enum.flat_map(holders, fn {user_id, current, current_rank} ->
      with %{} = next <- Ranks.next_rank(ranks, current_rank),
           %{ready: true} = progress <-
             Ranks.progress(
               next,
               current.awarded_on,
               Map.get(attended, user_id, 0),
               today,
               Map.get(checks_by_user, user_id, []),
               ladder.ready_criteria || ["classes", "days"]
             ) do
        [
          %{
            user_id: user_id,
            nickname: nickname(user_id),
            ladder: %{id: ladder.id, name: ladder.name, style: ladder.style},
            current: %{
              rank: RankStanding.present_rank(current_rank),
              stripes: current.stripes
            },
            next: RankStanding.present_rank(next),
            progress: progress
          }
        ]
      else
        _not_ready -> []
      end
    end)
  end

  defp scope(context) do
    case AuthorizeClientAccess.client_ids(context, :manage_coaching) do
      :all ->
        {:ok, :all}

      ids ->
        if Organizations.capability_scope(context, :manage_coaching),
          do: {:ok, ids},
          else: {:error, :forbidden}
    end
  end

  defp nickname(user_id) do
    case Identity.find_by_id(user_id) do
      %{nickname: name} when is_binary(name) -> name
      _missing -> nil
    end
  end
end
