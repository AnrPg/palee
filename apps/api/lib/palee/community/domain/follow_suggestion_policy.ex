defmodule Palee.Community.Domain.FollowSuggestionPolicy do
  @moduledoc """
  «Ίσως γνωρίζεις» (ADR-561): ranks people to follow. Pure and
  deterministic: the same viewer, candidates and rates always give the same
  suggestions in the same order, whatever the input order.

  **Viewer** `%{following, buddies, clubs, boxes, has_area, disciplines}`:
  how much the person has to go on. `maturity/1` turns it into 0..1, which
  slides every weight from its broad (cold-start) value to its personal one.
  A new person is ranked mostly by their boxes, coaches, disciplines, area,
  activity and popularity; a person with a network mostly by common follows
  and open clubs. There is no cut-off: every follow, Buddy and club moves it
  a little.

  **Candidate** (from the store): `%{user_id, follows_me, box_id, box_name,
  box_coach, mutual_count, mutual_ids, club_id, club_name,
  shared_disciplines, nearby, via_seed, followers, active_days, newcomer,
  private}`.

  **Signals** (`signals/0`), each valued 0..1 by `values/2`:
  `follows_you`, `box`, `coach`, `mutual`, `club`, `sport`, `nearby`,
  `via_person`, `popular` (followers, relative to the best-followed
  candidate), `active` (days with posts or training lately, never shown)
  and `newcomer` (new on Palee or in the shared box).

  **Score** = Σ weight(signal, maturity) × learned(signal) × value. The
  learned factor (`learned_factors/1`) comes from anonymous counters of
  which shown reasons led to follows, smoothed towards the overall rate and
  bounded, so a few clicks cannot swing it. Ties break by user id.

  **Variety**: the n-th suggestion with the same shown reason keeps
  `variety_decay^(n-1)` of its score, so one box cannot fill the list.

  **Reason**: each suggestion shows the explainable signal that contributed
  most (`reasons/0`); `active` is never shown, so nobody learns when
  someone trains. All the tuning lives in `weights/0`, `learning/0` and
  `variety_decay/0`.
  """

  @signals ~w(follows_you box coach mutual club sport nearby via_person popular active newcomer)a
  @shown ~w(follows_you via_person mutual coach box club sport nearby popular newcomer)a
  @reasons Enum.map(@shown, &Atom.to_string/1) ++ ["for_you"]
  @events ~w(shown followed dismissed)

  # {broad, personal}: the weight for a person with nothing to go on, and
  # for one with a settled network. Tuning is one change here.
  @weights %{
    follows_you: {5.0, 5.0},
    via_person: {3.0, 3.0},
    box: {4.0, 2.0},
    coach: {5.0, 2.5},
    mutual: {1.0, 4.0},
    club: {2.0, 3.0},
    sport: {2.0, 1.5},
    nearby: {1.5, 0.75},
    popular: {1.5, 0.25},
    active: {1.5, 0.5},
    newcomer: {1.0, 0.5}
  }

  # The viewer's evidence: a follow counts once, a Buddy twice more (a
  # two-way tie), an open club and a box once. `half` evidence is maturity 0.5.
  @maturity %{follow: 1, buddy: 2, club: 1, box: 1, half: 10}

  # Learned factors: `prior` pseudo-impressions at the overall rate keep a
  # reason near 1.0 until it has real numbers; `min_shown` overall shows
  # before anything is learned; the factor stays within `bounds`.
  @learning %{prior: 200, min_shown: 500, bounds: {0.5, 2.0}, window_days: 90}

  @variety_decay 0.85
  @mutual_names 2
  @recent_days 30
  @active_half_days 4

  def signals, do: @signals
  def reasons, do: @reasons
  def events, do: @events
  def weights, do: @weights
  def learning, do: @learning
  def variety_decay, do: @variety_decay

  @doc "The window activity and newcomers are counted in: `now - 30 days`."
  def recent_since(%DateTime{} = now), do: DateTime.add(now, -@recent_days * 86_400, :second)

  @doc "The first day counters are read from for learning."
  def learning_since(%DateTime{} = now),
    do: now |> DateTime.to_date() |> Date.add(-@learning.window_days)

  @doc """
  0.0 for a person with nothing to go on, approaching 1.0 as their network
  grows: `evidence / (evidence + half)`.
  """
  def maturity(viewer) when is_map(viewer) do
    evidence =
      count(viewer, :following) * @maturity.follow +
        count(viewer, :buddies) * @maturity.buddy +
        count(viewer, :clubs) * @maturity.club +
        count(viewer, :boxes) * @maturity.box

    evidence / (evidence + @maturity.half)
  end

  @doc "A signal's weight at `maturity` (0..1), sliding from broad to personal."
  def weight(signal, maturity) when is_number(maturity) do
    {broad, personal} = Map.fetch!(@weights, signal)
    m = maturity |> max(0.0) |> min(1.0)
    broad + (personal - broad) * m
  end

  @doc """
  Learned factor per shown reason from `[%{reason, event, count}]` counters:
  `(followed + prior × overall) / (shown + prior)` over the overall rate,
  bounded. Every reason is 1.0 until enough suggestions were shown overall.
  """
  def learned_factors(rows) when is_list(rows) do
    totals =
      Enum.reduce(rows, %{}, fn row, acc ->
        reason = to_string(row.reason)
        event = to_string(row.event)
        Map.update(acc, {reason, event}, row.count, &(&1 + row.count))
      end)

    shown = sum(totals, "shown")
    followed = sum(totals, "followed")

    if shown < @learning.min_shown or followed == 0 do
      %{}
    else
      overall = followed / shown
      {low, high} = @learning.bounds

      Map.new(@shown, fn signal ->
        reason = Atom.to_string(signal)
        s = Map.get(totals, {reason, "shown"}, 0)
        f = Map.get(totals, {reason, "followed"}, 0)
        rate = (f + @learning.prior * overall) / (s + @learning.prior)
        {signal, (rate / overall) |> max(low) |> min(high)}
      end)
    end
  end

  @doc "Each signal's value 0..1 for one candidate; `max_followers` normalises `popular`."
  def values(candidate, max_followers) do
    followers = Map.get(candidate, :followers) || 0
    mutual = Map.get(candidate, :mutual_count) || 0
    sports = length(Map.get(candidate, :shared_disciplines) || [])
    active = Map.get(candidate, :active_days) || 0

    %{
      follows_you: flag(candidate[:follows_me]),
      via_person: flag(candidate[:via_seed]),
      # A coach (or owner) of the viewer's box counts as coach instead of box.
      box: flag(not is_nil(candidate[:box_id]) and candidate[:box_coach] != true),
      coach: flag(not is_nil(candidate[:box_id]) and candidate[:box_coach] == true),
      mutual: saturate(mutual, 1),
      club: flag(not is_nil(candidate[:club_id])),
      sport: saturate(sports, 1),
      nearby: flag(candidate[:nearby]),
      popular: popularity(followers, max_followers),
      active: saturate(active, @active_half_days),
      newcomer: flag(candidate[:newcomer])
    }
  end

  @doc """
  Ranked suggestions for `%{viewer, candidates, learned, limit}`: at most
  `limit` maps `%{user_id, reason, score, private, box, club, mutual_count,
  mutual_ids, sport}`, best first.
  """
  def rank(%{viewer: viewer, candidates: candidates, limit: limit} = input)
      when is_integer(limit) and limit > 0 do
    learned = Map.get(input, :learned, %{})
    maturity = maturity(viewer)

    candidates =
      candidates
      |> Enum.sort_by(&{to_string(&1.user_id), &1})
      |> Enum.uniq_by(& &1.user_id)

    max_followers =
      candidates |> Enum.map(&(Map.get(&1, :followers) || 0)) |> Enum.max(fn -> 0 end)

    candidates
    |> Enum.map(&score(&1, maturity, learned, max_followers))
    |> Enum.filter(&(&1.score > 0))
    |> Enum.sort_by(&{-&1.score, to_string(&1.candidate.user_id)})
    |> diversify()
    |> Enum.take(limit)
    |> Enum.map(&present/1)
  end

  @doc "Whether `reason` and `event` are ones the counters know."
  def countable?(reason, event), do: reason in @reasons and event in @events

  # ------------------------------------------------------------ internals

  defp score(candidate, maturity, learned, max_followers) do
    contributions =
      candidate
      |> values(max_followers)
      |> Map.new(fn {signal, value} ->
        {signal, weight(signal, maturity) * Map.get(learned, signal, 1.0) * value}
      end)

    %{
      candidate: candidate,
      score: contributions |> Map.values() |> Enum.sum(),
      reason: reason(contributions)
    }
  end

  # The shown signal that contributed most; earlier in @shown wins a tie.
  defp reason(contributions) do
    @shown
    |> Enum.with_index()
    |> Enum.filter(fn {signal, _i} -> Map.fetch!(contributions, signal) > 0 end)
    |> Enum.max_by(fn {signal, i} -> {Map.fetch!(contributions, signal), -i} end, fn -> nil end)
    |> case do
      nil -> "for_you"
      {signal, _i} -> Atom.to_string(signal)
    end
  end

  # Greedy: repeatedly take the best adjusted score, where the n-th pick of
  # a reason already taken keeps decay^n of its score. Stable on ties.
  defp diversify(scored), do: diversify(scored, %{}, [])

  defp diversify([], _taken, acc), do: Enum.reverse(acc)

  defp diversify(remaining, taken, acc) do
    best =
      remaining
      |> Enum.with_index()
      |> Enum.max_by(fn {item, i} ->
        {item.score * :math.pow(@variety_decay, Map.get(taken, item.reason, 0)), -i}
      end)
      |> elem(0)

    diversify(
      List.delete(remaining, best),
      Map.update(taken, best.reason, 1, &(&1 + 1)),
      [best | acc]
    )
  end

  defp present(%{candidate: c, score: score, reason: reason}) do
    %{
      user_id: c.user_id,
      reason: reason,
      score: Float.round(score * 1.0, 4),
      private: c[:private] == true,
      box: if(c[:box_id], do: %{id: c.box_id, name: c[:box_name]}),
      club: if(c[:club_id], do: %{id: c.club_id, name: c[:club_name]}),
      mutual_count: c[:mutual_count] || 0,
      mutual_ids: Enum.take(c[:mutual_ids] || [], @mutual_names),
      sport: List.first(c[:shared_disciplines] || [])
    }
  end

  defp count(map, key) do
    case Map.get(map, key) do
      n when is_integer(n) and n > 0 -> n
      _other -> 0
    end
  end

  defp sum(totals, event) do
    totals
    |> Enum.filter(fn {{_reason, e}, _n} -> e == event end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sum()
  end

  defp flag(true), do: 1.0
  defp flag(_other), do: 0.0

  # 0 → 0, half → 0.5, growing towards 1.
  defp saturate(n, half) when is_integer(n) and n > 0, do: n / (n + half)
  defp saturate(_n, _half), do: 0.0

  defp popularity(followers, max) when followers > 0 and max > 0,
    do: :math.log(1 + followers) / :math.log(1 + max)

  defp popularity(_followers, _max), do: 0.0
end
