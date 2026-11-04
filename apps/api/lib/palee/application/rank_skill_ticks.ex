defmodule Palee.Application.RankSkillTicks do
  @moduledoc """
  A coach ticks skills of a rank (ADR-400 and its follow-up): one skill for
  one client (the client's profile), one skill for several people at once
  (a class) and the skills ticked at a promotion. All three write the same
  `rank_skill_checks`, by the skill's stable id. `manage_coaching`: a coach
  reaches their own clients, staff with full coaching scope everyone
  (ADR-100). The person is told later, in one grouped notice
  (`RankSkillNotices`).
  """

  alias Palee.Application.{AuthorizeClientAccess, Clock, RankSkillNotices}
  alias Palee.Ranks

  @max_people 100

  @doc "Ticks or unticks (`checked: false`) one skill for one client."
  def check(%{organization_id: organization_id} = context, staff_id, user_id, params) do
    with :ok <- AuthorizeClientAccess.call(context, :manage_coaching, user_id),
         {:ok, on} <- check_date(get(params, "checked_on"), Clock.today()),
         :ok <-
           Ranks.with_context(context, fn ->
             with {:ok, rank} <- fetch_rank(get(params, "rank_id")),
                  {:ok, {skill_id, skill}} <- find_skill(rank, params) do
               write(get(params, "checked"), %{
                 organization_id: organization_id,
                 user_id: user_id,
                 rank_id: rank.id,
                 skill_id: skill_id,
                 skill: skill,
                 checked_on: on,
                 checked_by_id: staff_id,
                 note: get(params, "note")
               })
             end
           end) do
      if get(params, "checked") != false, do: RankSkillNotices.schedule(context, user_id)
      :ok
    end
  end

  @doc """
  The class view («Δεξιότητα» in a class, mockup 3B): the ladders with their
  skills, and for each of `user_ids` whether the coach reaches them, the
  rank they work towards on each ladder and the skills already ticked.
  """
  def class_view(context, user_ids) do
    with {:ok, user_ids} <- people(user_ids),
         {:ok, reachable} <- reachable(context, user_ids) do
      {ladders, awards, checks} =
        Ranks.with_context(context, fn ->
          reached = Enum.filter(user_ids, &(&1 in reachable))

          {Ranks.list_ladders(), Ranks.list_awards_for(reached),
           Ranks.list_skill_checks_for(reached)}
        end)

      people =
        Enum.map(user_ids, fn user_id ->
          if user_id in reachable do
            %{
              user_id: user_id,
              reachable: true,
              next_rank_ids: next_rank_ids(ladders, for_user(awards, user_id)),
              checked:
                checks
                |> for_user(user_id)
                |> Enum.filter(& &1.skill_id)
                |> Enum.map(&%{rank_id: &1.rank_id, skill_id: &1.skill_id})
            }
          else
            %{user_id: user_id, reachable: false, next_rank_ids: [], checked: []}
          end
        end)

      {:ok,
       %{
         ladders: Enum.map(ladders, &Palee.Application.RankStanding.present_ladder/1),
         people: people
       }}
    end
  end

  @doc """
  Ticks (or unticks) one skill for several people at once. Only people the
  coach reaches and who work towards that skill's rank (it is their next
  rank on its ladder) are changed; the others are listed as skipped with
  the reason (`not_your_client`, `other_rank`).
  """
  def batch(%{organization_id: organization_id} = context, staff_id, params) do
    with {:ok, user_ids} <- people(get(params, "user_ids")),
         {:ok, reachable} <- reachable(context, user_ids),
         {:ok, on} <- check_date(get(params, "checked_on"), Clock.today()) do
      checked = get(params, "checked")

      result =
        Ranks.with_context(context, fn ->
          with {:ok, rank} <- fetch_rank(get(params, "rank_id")),
               {:ok, {skill_id, skill}} <- find_skill(rank, params) do
            ladder = Enum.find(Ranks.list_ladders(), &(&1.id == rank.ladder_id))
            reached = Enum.filter(user_ids, &(&1 in reachable))
            awards = Ranks.list_awards_for(reached)

            Enum.reduce_while(user_ids, {:ok, [], []}, fn user_id, {:ok, done, skipped} ->
              cond do
                user_id not in reachable ->
                  {:cont, {:ok, done, [skip(user_id, "not_your_client") | skipped]}}

                rank.id not in next_rank_ids([ladder], for_user(awards, user_id)) ->
                  {:cont, {:ok, done, [skip(user_id, "other_rank") | skipped]}}

                true ->
                  case write(checked, %{
                         organization_id: organization_id,
                         user_id: user_id,
                         rank_id: rank.id,
                         skill_id: skill_id,
                         skill: skill,
                         checked_on: on,
                         checked_by_id: staff_id
                       }) do
                    :ok -> {:cont, {:ok, [user_id | done], skipped}}
                    error -> {:halt, error}
                  end
              end
            end)
          end
        end)

      with {:ok, done, skipped} <- result do
        if checked != false, do: Enum.each(done, &RankSkillNotices.schedule(context, &1))
        {:ok, %{updated: Enum.reverse(done), skipped: Enum.reverse(skipped)}}
      end
    end
  end

  @doc """
  At a promotion (mockup 3C): the skills ticked on the promotion sheet
  become ticks of that rank too, dated the day of the promotion; a skill
  already ticked keeps its date and note. Runs in the box's session.
  """
  def from_award(award, rank, skills, staff_id) do
    ticked =
      award.user_id
      |> Ranks.list_skill_checks()
      |> Enum.filter(&(&1.rank_id == rank.id))
      |> MapSet.new(& &1.skill_id)

    rank
    |> Ranks.skill_entries()
    |> Enum.filter(fn {id, name} -> name in skills and is_binary(id) and id not in ticked end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.reduce_while(:ok, fn {id, name}, :ok ->
      case write(true, %{
             organization_id: award.organization_id,
             user_id: award.user_id,
             rank_id: rank.id,
             skill_id: id,
             skill: name,
             checked_on: award.awarded_on,
             checked_by_id: staff_id,
             # A promotion is its own news: these ticks are never told again.
             notified_at: Clock.now()
           }) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp skip(user_id, reason), do: %{user_id: user_id, reason: reason}

  defp for_user(rows, user_id), do: Enum.filter(rows, &(&1.user_id == user_id))

  # The rank a person works towards on each ladder: after their current
  # rank, or the first one when they hold none.
  defp next_rank_ids(ladders, awards) do
    Enum.flat_map(ladders, fn
      nil ->
        []

      ladder ->
        ranks = Enum.sort_by(ladder.ranks, & &1.position)
        current = awards |> Enum.filter(&(&1.ladder_id == ladder.id)) |> Ranks.current_award()
        current_rank = current && Enum.find(ranks, &(&1.id == current.rank_id))

        case Ranks.next_rank(ranks, current_rank) do
          nil -> []
          next -> [next.id]
        end
    end)
  end

  defp people(user_ids) when is_list(user_ids) and user_ids != [] do
    ids =
      Enum.flat_map(user_ids, fn id ->
        case Ecto.UUID.cast(id) do
          {:ok, id} -> [id]
          :error -> []
        end
      end)

    if length(ids) == length(user_ids) and length(ids) <= @max_people,
      do: {:ok, Enum.uniq(ids)},
      else: {:error, :invalid_rank_award}
  end

  defp people(text) when is_binary(text),
    do: text |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> people()

  defp people(_other), do: {:error, :invalid_rank_award}

  defp reachable(context, user_ids) do
    case AuthorizeClientAccess.client_ids(context, :manage_coaching) do
      :all ->
        {:ok, user_ids}

      ids when is_list(ids) ->
        if Palee.Organizations.capability_scope(context, :manage_coaching),
          do: {:ok, Enum.filter(user_ids, &(&1 in ids))},
          else: {:error, :forbidden}
    end
  end

  defp write(false, check),
    do: Ranks.delete_skill_check(check.user_id, check.rank_id, check.skill_id)

  defp write(_checked, check) do
    case Ranks.put_skill_check(check) do
      {:ok, _check} -> :ok
      {:error, _changeset} -> {:error, :invalid_rank_award}
    end
  end

  defp find_skill(rank, params) do
    case Ranks.find_skill(rank, get(params, "skill_id"), get(params, "skill")) do
      {:ok, {id, _name} = found} when is_binary(id) -> {:ok, found}
      _missing -> {:error, :unknown_skills}
    end
  end

  defp fetch_rank(id) do
    with {:ok, id} <- Ecto.UUID.cast(id || ""),
         rank when not is_nil(rank) <-
           Enum.find_value(Ranks.list_ladders(), fn ladder ->
             Enum.find(ladder.ranks, &(&1.id == id))
           end) do
      {:ok, rank}
    else
      _missing -> {:error, :unknown_rank}
    end
  end

  defp check_date(nil, today), do: {:ok, today}
  defp check_date(%Date{} = date, today), do: future_check(date, today)

  defp check_date(text, today) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> future_check(date, today)
      _error -> {:error, :invalid_rank_award}
    end
  end

  defp check_date(_other, _today), do: {:error, :invalid_rank_award}

  defp future_check(date, today) do
    if Date.compare(date, today) == :gt, do: {:error, :award_in_future}, else: {:ok, date}
  end

  defp params_map(params) when is_struct(params), do: params |> Map.from_struct() |> params_map()

  defp params_map(params) when is_map(params),
    do: Map.new(params, fn {k, v} -> {to_string(k), v} end)

  defp get(params, key), do: Map.get(params_map(params), key)
end
