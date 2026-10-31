defmodule Palee.Gamification.Domain.LeaderboardFiltersTest do
  use ExUnit.Case, async: true

  alias Palee.Gamification.Domain.{LeaderboardFilters, ScorePercentile}

  describe "parse/1" do
    test "blank means all, defaults to the box and the day" do
      assert {:ok, %LeaderboardFilters{scope: "box", window: "day", division: nil, buddies: false}} =
               LeaderboardFilters.parse(%{"division" => "", "scale" => " "})
    end

    test "reads every filter, string or atom keys" do
      assert {:ok, filters} =
               LeaderboardFilters.parse(%{
                 division: "women",
                 age_group: "35_39",
                 scale: "rx",
                 scope: "branch",
                 location_id: "loc",
                 window: "month",
                 date: "2026-10-31",
                 buddies: "true"
               })

      assert %{division: "women", age_group: "35_39", scale: "rx", location_id: "loc"} = filters
      assert filters.date == ~D[2026-10-31]
      assert filters.buddies
    end

    test "names the field that does not read" do
      assert {:error, {:invalid_leaderboard_filter, :division}} =
               LeaderboardFilters.parse(%{"division" => "other"})

      assert {:error, {:invalid_leaderboard_filter, :location_id}} =
               LeaderboardFilters.parse(%{"scope" => "branch"})

      assert {:error, {:invalid_leaderboard_filter, :date}} =
               LeaderboardFilters.parse(%{"date" => "31/10"})

      assert {:error, {:invalid_leaderboard_filter, :window}} =
               LeaderboardFilters.parse(%{"window" => "decade"})
    end
  end

  describe "age groups" do
    test "use the age reached during the year" do
      assert LeaderboardFilters.age_group(2010, 2026) == "under_18"
      assert LeaderboardFilters.age_group(2008, 2026) == "18_34"
      assert LeaderboardFilters.age_group(1992, 2026) == "18_34"
      assert LeaderboardFilters.age_group(1991, 2026) == "35_39"
      assert LeaderboardFilters.age_group(1984, 2026) == "40_44"
      assert LeaderboardFilters.age_group(1964, 2026) == "60_64"
      assert LeaderboardFilters.age_group(1961, 2026) == "65_plus"
      assert LeaderboardFilters.age_group(nil, 2026) == nil
    end
  end

  test "keep?/3 applies every filter and a person without a division only passes «all»" do
    {:ok, filters} = LeaderboardFilters.parse(%{"division" => "men", "age_group" => "40_44"})
    man_41 = %{division: "men", birth_year: 1985}

    assert LeaderboardFilters.keep?(filters, man_41, 2026)
    refute LeaderboardFilters.keep?(filters, %{division: "women", birth_year: 1985}, 2026)
    refute LeaderboardFilters.keep?(filters, %{division: nil, birth_year: 1985}, 2026)
    refute LeaderboardFilters.keep?(filters, %{division: "men", birth_year: nil}, 2026)

    {:ok, all} = LeaderboardFilters.parse(%{})
    assert LeaderboardFilters.keep?(all, %{}, 2026)

    {:ok, branch} = LeaderboardFilters.parse(%{"scope" => "branch", "location_id" => "a"})
    assert LeaderboardFilters.keep?(branch, %{home_location_id: "a"}, 2026)
    refute LeaderboardFilters.keep?(branch, %{home_location_id: "b"}, 2026)

    {:ok, buddies} = LeaderboardFilters.parse(%{"buddies" => true, "scale" => "rx"})
    assert LeaderboardFilters.keep?(buddies, %{buddy?: true, scale_level_slug: "rx"}, 2026)
    refute LeaderboardFilters.keep?(buddies, %{buddy?: false, scale_level_slug: "rx"}, 2026)
    refute LeaderboardFilters.keep?(buddies, %{buddy?: true, scale_level_slug: "scaled"}, 2026)
  end

  test "window/2 is the day, ISO week, month, year or everything" do
    date = ~D[2026-10-29]
    assert LeaderboardFilters.window("day", date) == {date, ~D[2026-10-30]}
    assert LeaderboardFilters.window("week", date) == {~D[2026-10-26], ~D[2026-11-02]}
    assert LeaderboardFilters.window("month", date) == {~D[2026-10-01], ~D[2026-11-01]}
    assert LeaderboardFilters.window("year", date) == {~D[2026-01-01], ~D[2027-01-01]}
    assert LeaderboardFilters.window("all", date) == nil
  end

  describe "ScorePercentile" do
    test "nothing below five results" do
      rows = Enum.map(1..4, &%{rank: &1})
      assert Enum.all?(ScorePercentile.annotate(rows), &(&1.percentile == nil))
    end

    test "percentile is the share of the others beaten, top_percent rounds up" do
      rows = ScorePercentile.annotate(Enum.map(1..10, &%{rank: &1}))

      assert %{percentile: 100, top_percent: 10} = Enum.at(rows, 0)
      assert %{percentile: 66, top_percent: 40} = Enum.at(rows, 3)
      assert %{percentile: 0, top_percent: 100} = Enum.at(rows, 9)
    end

    test "ties share a place and beat nobody they tie with; unranked rows get nil" do
      rows =
        ScorePercentile.annotate([
          %{rank: 1},
          %{rank: 1},
          %{rank: 3},
          %{rank: 4},
          %{rank: 5},
          %{rank: nil}
        ])

      assert [%{percentile: 75, top_percent: 40}, %{percentile: 75} | _] = rows
      assert %{percentile: nil, top_percent: nil} = List.last(rows)
    end
  end
end
