defmodule Palee.Application.FollowSuggestions do
  @moduledoc """
  «Ίσως γνωρίζεις» (ADR-561): people to follow, in the member's personal
  session. The store gathers candidates and facts, the domain policy ranks
  them and picks one reason each, and this service adds names and avatars,
  follows, dismisses and keeps the anonymous per-reason counters the engine
  learns from (shown, followed, dismissed).

  `seed` (a person's id) adds «Και αυτοί ίσως» on that person's profile:
  the people they follow, when the viewer may see them.
  """

  alias Palee.Application.Follows
  alias Palee.Community.FollowSuggestions, as: Engine
  alias Palee.Identity

  # How many candidates each store source contributes before ranking.
  @pool 100
  @max_limit 50

  def max_limit, do: @max_limit

  @doc """
  Up to `limit` (1..50) ranked suggestions:
  `%{people: [%{id, nickname, handle, avatar_url, private, reason}]}`.
  """
  def list(%{user_id: _} = context, params, now \\ DateTime.utc_now()) do
    with {:ok, limit} <- limit(params),
         {:ok, seed} <- seed(params) do
      viewer = Engine.viewer(context)
      candidates = Engine.candidates(context, seed, @pool, Engine.recent_since(now))
      learned = context |> Engine.rates(Engine.learning_since(now)) |> Engine.learned_factors()

      ranked =
        Engine.rank(%{viewer: viewer, candidates: candidates, learned: learned, limit: limit})

      people = people(ranked)
      ranked = Enum.filter(ranked, &Map.has_key?(people, &1.user_id))
      count_shown(context, ranked)

      {:ok, %{people: Enum.map(ranked, &present(&1, people))}}
    end
  end

  @doc "Follows a suggested person and counts it for the reason shown."
  def follow(context, target_id, reason) do
    with {:ok, reason} <- reason(reason),
         {:ok, status} <- Follows.follow(context, "user", target_id) do
      :ok = Engine.count(context, reason, "followed", 1)
      {:ok, status}
    end
  end

  @doc "✕: the person is not suggested again unless they start following the viewer."
  def dismiss(%{user_id: user_id} = context, target_id, reason, now \\ DateTime.utc_now()) do
    with {:ok, target_id} <- uuid(target_id),
         {:ok, reason} <- reason(reason) do
      :ok = Engine.dismiss(context, user_id, target_id, now)
      :ok = Engine.count(context, reason, "dismissed", 1)
      :ok
    end
  end

  @doc "Undo of ✕."
  def undismiss(%{user_id: user_id} = context, target_id) do
    with {:ok, target_id} <- uuid(target_id) do
      Engine.undismiss(context, user_id, target_id)
    end
  end

  # ------------------------------------------------------------ internals

  defp limit(params) do
    case Map.get(params, :limit) || Map.get(params, "limit") do
      nil -> {:ok, @max_limit}
      n when is_integer(n) and n in 1..@max_limit -> {:ok, n}
      _other -> {:error, :invalid_follow_suggestion_limit}
    end
  end

  defp seed(params) do
    case Map.get(params, :seed) || Map.get(params, "seed") do
      nil -> {:ok, nil}
      seed -> uuid(seed)
    end
  end

  defp reason(reason) when is_binary(reason) do
    if reason in Engine.reasons(),
      do: {:ok, reason},
      else: {:error, :invalid_follow_suggestion_reason}
  end

  defp reason(_reason), do: {:error, :invalid_follow_suggestion_reason}

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp people(ranked) do
    ranked
    |> Enum.flat_map(&[&1.user_id | &1.mutual_ids])
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, &1})
  end

  defp count_shown(context, ranked) do
    ranked
    |> Enum.frequencies_by(& &1.reason)
    |> Enum.sort()
    |> Enum.each(fn {reason, n} -> :ok = Engine.count(context, reason, "shown", n) end)
  end

  defp present(suggestion, people) do
    person = Map.fetch!(people, suggestion.user_id)

    %{
      id: suggestion.user_id,
      nickname: person.nickname,
      handle: Map.get(person, :handle),
      avatar_url: Map.get(person, :avatar_url),
      private: suggestion.private,
      reason: %{
        kind: suggestion.reason,
        box: suggestion.box,
        club: suggestion.club,
        sport: suggestion.sport,
        mutual_count: suggestion.mutual_count,
        mutuals:
          suggestion.mutual_ids
          |> Enum.flat_map(fn id ->
            case Map.get(people, id) do
              nil -> []
              p -> [%{id: id, nickname: p.nickname}]
            end
          end)
      }
    }
  end
end
