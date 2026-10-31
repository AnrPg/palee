defmodule Palee.ReviewAsks.ReviewAskPolicyTest do
  @moduledoc "ADR-355: who is asked for a Google review, the same way for everyone."

  use ExUnit.Case, async: true

  alias Palee.ReviewAsks.Domain.ReviewAskPolicy

  @now ~U[2026-11-02 10:00:00.000000Z]
  @settings %{
    enabled: true,
    google_place_id: "ChIJN1t_tDeuEmsRUsoyG83frY4",
    milestones: [10, 50, 100]
  }
  @facts %{
    active_membership: true,
    member_since: ~U[2026-01-01 00:00:00Z],
    attendance_count: 11,
    last_attended_at: ~U[2026-11-02 08:00:00Z]
  }

  defp decide(overrides \\ %{}, asks \\ [], opted_out \\ false, hour \\ 10) do
    settings = Map.merge(@settings, Map.get(overrides, :settings, %{}))
    facts = Map.merge(@facts, Map.get(overrides, :facts, %{}))
    ReviewAskPolicy.decide(settings, facts, asks, opted_out, hour, @now)
  end

  test "a member just past a milestone, after a class, by day, is asked" do
    assert {:ask, 10} = decide()
    assert {:ask, 50} = decide(%{facts: %{attendance_count: 54}})
  end

  test "every rule is a behavioural fact, never an opinion" do
    assert {:skip, :off} = decide(%{settings: %{enabled: false}})
    assert {:skip, :off} = decide(%{settings: %{google_place_id: nil}})
    assert {:skip, :opted_out} = decide(%{}, [], true)
    assert {:skip, :no_membership} = decide(%{facts: %{active_membership: false}})
    assert {:skip, :new_member} = decide(%{facts: %{member_since: ~U[2026-10-20 00:00:00Z]}})
    assert {:skip, :night} = decide(%{}, [], false, 22)
    assert {:skip, :night} = decide(%{}, [], false, 7)

    assert {:skip, :not_after_class} =
             decide(%{facts: %{last_attended_at: ~U[2026-10-30 08:00:00Z]}})

    assert {:skip, :no_milestone} = decide(%{facts: %{attendance_count: 9}})
    assert {:skip, :no_milestone} = decide(%{facts: %{attendance_count: 15}})
  end

  test "asked milestones, the cooldown and the lifetime cap" do
    old = %{milestone: 10, shown_at: ~U[2026-01-01 00:00:00Z], status: "opened"}
    assert {:skip, :no_milestone} = decide(%{}, [old])
    assert {:ask, 50} = decide(%{facts: %{attendance_count: 50}}, [old])

    recent = %{old | shown_at: ~U[2026-09-01 00:00:00Z]}
    assert {:skip, :cooldown} = decide(%{facts: %{attendance_count: 50}}, [recent])

    three = for m <- [3, 4, 5], do: %{old | milestone: m}
    assert {:skip, :asked_enough} = decide(%{facts: %{attendance_count: 50}}, three)
  end

  test "an unanswered ask is shown again within a day" do
    open = %{status: "shown", shown_at: DateTime.add(@now, -3_600)}
    assert ReviewAskPolicy.open_ask([open], @now) == open
    refute ReviewAskPolicy.open_ask([%{open | shown_at: DateTime.add(@now, -90_000)}], @now)
    refute ReviewAskPolicy.open_ask([%{open | status: "later"}], @now)
  end

  test "answers" do
    assert {:ok, %{status: "opened", responded_at: @now}} =
             ReviewAskPolicy.respond(%{status: "shown"}, "opened", @now)

    assert {:ok, %{}} = ReviewAskPolicy.respond(%{status: "opened"}, "opened", @now)

    assert {:error, :review_ask_answered} =
             ReviewAskPolicy.respond(%{status: "opened"}, "later", @now)

    assert {:error, :invalid_review_action} =
             ReviewAskPolicy.respond(%{status: "shown"}, "5 stars", @now)
  end

  test "settings: a Place ID is needed to turn asks on" do
    defaults = ReviewAskPolicy.default_settings()

    assert {:error, {:invalid_fields, %{google_place_id: "required"}}} =
             ReviewAskPolicy.changes(defaults, %{"enabled" => true})

    assert {:error, {:invalid_fields, %{google_place_id: "invalid", milestones: "invalid"}}} =
             ReviewAskPolicy.changes(defaults, %{
               "google_place_id" => "bad id!",
               "milestones" => [1]
             })

    assert {:ok,
            %{enabled: true, google_place_id: "ChIJN1t_tDeuEmsRUsoyG83frY4", milestones: [10, 25]}} =
             ReviewAskPolicy.changes(defaults, %{
               "enabled" => true,
               "google_place_id" => " ChIJN1t_tDeuEmsRUsoyG83frY4 ",
               "milestones" => [25, 10, 25]
             })
  end

  test "Google links" do
    assert ReviewAskPolicy.write_review_url("ChIJabc_123-xyz") ==
             "https://search.google.com/local/writereview?placeid=ChIJabc_123-xyz"

    assert ReviewAskPolicy.read_reviews_url("ChIJabc_123-xyz") =~ "place_id:ChIJabc_123-xyz"
    assert ReviewAskPolicy.write_review_url(nil) == nil
  end
end
