defmodule Palee.Community.Domain.FollowSuggestionPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Community.Domain.FollowSuggestionPolicy, as: Policy

  @new %{following: 0, buddies: 0, clubs: 0, boxes: 1}
  @settled %{following: 40, buddies: 15, clubs: 3, boxes: 1}

  defp person(n, facts),
    do: Map.merge(%{user_id: "00000000-0000-0000-0000-00000000000#{n}"}, Map.new(facts))

  defp rank(viewer, candidates, opts \\ []) do
    Policy.rank(%{
      viewer: viewer,
      candidates: candidates,
      learned: Keyword.get(opts, :learned, %{}),
      limit: Keyword.get(opts, :limit, 10)
    })
  end

  test "maturity grows with the network and never reaches 1" do
    assert Policy.maturity(%{}) == 0.0
    assert Policy.maturity(@new) < Policy.maturity(%{@new | following: 5})
    assert Policy.maturity(@settled) > 0.8
    assert Policy.maturity(@settled) < 1.0
  end

  test "a new person sees the box first, a settled one sees common follows first" do
    box_mate = person(1, box_id: "b", box_name: "Milos method")
    friend_of_friends = person(2, mutual_count: 3, mutual_ids: ["m1", "m2", "m3"])

    assert [%{user_id: first, reason: "box"} | _] = rank(@new, [friend_of_friends, box_mate])
    assert first == box_mate.user_id

    assert [%{user_id: first, reason: "mutual", mutual_ids: ["m1", "m2"]} | _] =
             rank(@settled, [box_mate, friend_of_friends])

    assert first == friend_of_friends.user_id
  end

  test "someone who follows you is the strongest reason, and a coach is shown as coach" do
    follower = person(1, follows_me: true)
    coach = person(2, box_id: "b", box_coach: true)
    mate = person(3, box_id: "b")

    assert [
             %{reason: "follows_you"},
             %{reason: "coach", box: %{id: "b"}},
             %{reason: "box"}
           ] = rank(@new, [mate, coach, follower])
  end

  test "activity orders people but is never the reason shown" do
    active = person(1, active_days: 12)
    assert [%{reason: "for_you"}] = rank(@new, [active])

    lively = person(2, nearby: true, active_days: 12)
    quiet = person(3, nearby: true)
    assert [%{user_id: first, reason: "nearby"}, _] = rank(@new, [quiet, lively])
    assert first == lively.user_id
  end

  test "people with no signal at all are not suggested" do
    assert rank(@new, [person(1, [])]) == []
  end

  test "variety: one box does not fill the list" do
    mates = for n <- 1..3, do: person(n, box_id: "b", followers: 1)

    sporty =
      person(4, shared_disciplines: ~w(crossfit running yoga), nearby: true, active_days: 12)

    reasons = rank(@new, [sporty | mates]) |> Enum.map(& &1.reason)
    assert Enum.take(reasons, 3) == ["box", "box", "sport"]
  end

  test "the same input in any order gives the same answer" do
    candidates = [
      person(1, box_id: "b"),
      person(2, follows_me: true),
      person(3, shared_disciplines: ["yoga"], followers: 4),
      person(4, mutual_count: 1, mutual_ids: ["x"]),
      person(5, club_id: "c", club_name: "Τρέξιμο")
    ]

    assert rank(@settled, candidates) == rank(@settled, Enum.reverse(candidates))
    assert rank(@settled, candidates, limit: 2) == Enum.take(rank(@settled, candidates), 2)
  end

  describe "learned_factors/1" do
    test "nothing is learned before enough suggestions were shown" do
      assert Policy.learned_factors([]) == %{}

      assert Policy.learned_factors([
               %{reason: "box", event: "shown", count: 10},
               %{reason: "box", event: "followed", count: 9}
             ]) == %{}
    end

    test "reasons that lead to follows weigh more, within bounds" do
      factors =
        Policy.learned_factors([
          %{reason: "box", event: "shown", count: 5_000},
          %{reason: "box", event: "followed", count: 1_000},
          %{reason: "popular", event: "shown", count: 5_000},
          %{reason: "popular", event: "followed", count: 50}
        ])

      assert factors.box > 1.0
      assert factors.popular < 1.0
      assert factors.popular >= 0.5
      assert factors.box <= 2.0
      # Unseen reasons stay at the overall rate.
      assert_in_delta factors.club, 1.0, 1.0e-9
    end

    test "learned factors change the order" do
      sporty = person(1, shared_disciplines: ~w(crossfit running yoga))
      near = person(2, nearby: true)

      assert [%{reason: "sport"} | _] = rank(@new, [near, sporty])

      assert [%{reason: "nearby"} | _] =
               rank(@new, [near, sporty], learned: %{sport: 0.5, nearby: 2.0})
    end
  end

  test "counters only know the shown reasons and three events" do
    assert Policy.countable?("box", "shown")
    assert Policy.countable?("for_you", "dismissed")
    refute Policy.countable?("active", "shown")
    refute Policy.countable?("box", "clicked")
  end
end
