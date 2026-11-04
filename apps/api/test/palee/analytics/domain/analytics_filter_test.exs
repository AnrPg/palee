defmodule Palee.Analytics.Domain.AnalyticsFilterTest do
  @moduledoc "ADR-462: the staff analytics filter, k-anonymity and baselines."

  use ExUnit.Case, async: true

  alias Palee.Analytics.Domain.{
    AnalyticsFilter,
    EventCatalog,
    KAnonymity,
    MetricBaseline,
    MetricRegistry
  }

  alias Palee.Organizations.Domain.AccessPolicy

  @today ~D[2026-11-04]

  describe "period" do
    test "defaults to the last 30 days, the previous period ends the day before" do
      {:ok, filter} = AnalyticsFilter.parse(%{}, @today)
      assert {filter.from, filter.to, filter.days} == {~D[2026-10-06], @today, 30}

      previous = AnalyticsFilter.previous(filter)
      assert {previous.from, previous.to} == {~D[2026-09-06], ~D[2026-10-05]}
    end

    test "from/to win over days; days still works" do
      {:ok, filter} =
        AnalyticsFilter.parse(%{"from" => "2026-10-01", "to" => "2026-10-07"}, @today)

      assert filter.days == 7
      assert AnalyticsFilter.previous(filter).from == ~D[2026-09-24]

      {:ok, filter} = AnalyticsFilter.parse(%{"days" => "7"}, @today)
      assert filter.from == ~D[2026-10-29]
    end

    test "refuses a reversed or too long period and unknown values" do
      assert {:error, [to: _]} =
               AnalyticsFilter.parse(%{"from" => "2026-10-07", "to" => "2026-10-01"}, @today)

      assert {:error, [to: _]} = AnalyticsFilter.parse(%{"from" => "2020-01-01"}, @today)
      assert {:error, [days: _]} = AnalyticsFilter.parse(%{"days" => "0"}, @today)
      assert {:error, [levels: _]} = AnalyticsFilter.parse(%{"levels" => "expert"}, @today)
      assert {:error, [location_ids: _]} = AnalyticsFilter.parse(%{"location_ids" => "x"}, @today)
    end
  end

  test "dimensions parse from comma lists, unknown included for age and gender" do
    id = Ecto.UUID.generate()

    {:ok, filter} =
      AnalyticsFilter.parse(
        %{
          "class_type_ids" => id,
          "levels" => "advanced,beginner",
          "time_of_day" => "evening",
          "tenure_bands" => "lt_3m",
          "age_bands" => "unknown,35_44",
          "genders" => "unknown",
          "package_families" => "Unlimited"
        },
        @today
      )

    assert filter.class_type_ids == [id]
    assert filter.levels == ["beginner", "advanced"]
    assert filter.age_bands == ["35_44", "unknown"]
    assert filter.genders == ["unknown"]
    assert filter.package_families == ["unlimited"]
    assert AnalyticsFilter.people_filtered?(filter)
    assert AnalyticsFilter.demographic?(filter)
    assert AnalyticsFilter.classes_filtered?(filter)
    assert AnalyticsFilter.to_params(filter).previous_to == "2026-10-05"
  end

  test "age and tenure bands" do
    assert AnalyticsFilter.age_band(nil, @today) == "unknown"
    assert AnalyticsFilter.age_band(1990, @today) == "35_44"
    assert AnalyticsFilter.age_band(2010, @today) == "under_18"
    assert AnalyticsFilter.birth_years("35_44", @today) == {1982, 1991}
    assert AnalyticsFilter.tenure_band(~D[2026-10-01], @today) == "lt_3m"
    assert AnalyticsFilter.tenure_band(~D[2026-01-01], @today) == "3_12m"
    assert AnalyticsFilter.tenure_band(~D[2024-01-01], @today) == "gt_12m"
  end

  test "k-anonymity never returns the number of a group under five" do
    assert KAnonymity.bucket("women", 4) == %{key: "women", suppressed: true}
    assert KAnonymity.bucket("men", 5) == %{key: "men", people: 5, suppressed: false}
    assert KAnonymity.bucket("unknown", 0) == %{key: "unknown", suppressed: true}

    assert KAnonymity.suppress_rows([
             %{key: 7, count: 9, people: 3},
             %{key: 8, count: 9, people: 6}
           ]) ==
             [%{key: 7, suppressed: true}, %{key: 8, count: 9, people: 6}]
  end

  describe "baselines" do
    @start ~U[2026-10-06 00:00:00Z]
    @finish ~U[2026-11-05 00:00:00Z]
    @windows %{
      current: {@start, @finish},
      previous: {~U[2026-09-06 00:00:00Z], @start}
    }

    test "no baseline keeps both periods" do
      assert %{current: {@start, @finish}, previous: {_, @start}, since: nil} =
               MetricBaseline.windows(@windows, nil)
    end

    test "a baseline inside the period starts it there and drops the previous" do
      baseline = ~U[2026-10-20 12:00:00Z]

      assert %{current: {^baseline, @finish}, previous: nil, since: ^baseline} =
               MetricBaseline.windows(@windows, baseline)
    end

    test "a baseline inside the previous period cuts it" do
      baseline = ~U[2026-09-20 00:00:00Z]

      assert %{current: {@start, @finish}, previous: {^baseline, @start}} =
               MetricBaseline.windows(@windows, baseline)
    end

    test "the active baseline is the latest reset not undone" do
      resets = [
        %{metric_key: "a", reset_at: ~U[2026-10-01 00:00:00Z], undone_at: nil},
        %{
          metric_key: "a",
          reset_at: ~U[2026-10-10 00:00:00Z],
          undone_at: ~U[2026-10-11 00:00:00Z]
        },
        %{metric_key: "b", reset_at: ~U[2026-10-02 00:00:00Z], undone_at: nil}
      ]

      assert MetricBaseline.active(resets) == %{
               "a" => ~U[2026-10-01 00:00:00Z],
               "b" => ~U[2026-10-02 00:00:00Z]
             }
    end

    test "entries carry the delta, since and suppression" do
      {:ok, metric} = MetricRegistry.fetch(:organization, "training.no_show_rate")

      entry =
        MetricBaseline.entry(metric, %{value: 12.5, rows: []}, %{value: 10.0, rows: []}, nil)

      assert {entry.value, entry.previous, entry.delta, entry.since} == {12.5, 10.0, 2.5, nil}

      suppressed =
        MetricBaseline.entry(metric, %{suppressed: true}, nil, ~U[2026-10-01 00:00:00Z])

      assert {suppressed.value, suppressed.suppressed, suppressed.since} ==
               {nil, true, "2026-10-01T00:00:00Z"}
    end
  end

  describe "registry" do
    test "keys are unique per scope and validated" do
      for scope <- MetricRegistry.scopes() do
        keys = MetricRegistry.keys(scope)
        assert keys == Enum.uniq(keys)
      end

      assert {:ok, %{resettable: true}} =
               MetricRegistry.resettable(:organization, "training.class_fill_rate")

      assert {:error, :metric_not_resettable} =
               MetricRegistry.resettable(:organization, "finance.mrr")

      assert {:error, :unknown_metric} = MetricRegistry.fetch(:organization, "progress.totals")
      assert {:ok, _} = MetricRegistry.fetch(:member, "progress.totals")
      assert "finance.mrr" in MetricRegistry.section_keys(:finance)
    end
  end

  test "every event has an event-mix category" do
    for name <- EventCatalog.event_names() do
      assert EventCatalog.category(name) in EventCatalog.categories(), "#{name} has no category"
    end

    assert [
             %{
               category: "classes",
               total: 3,
               events: [%{name: "class_booking_requested", count: 2} | _]
             }
           ] =
             EventCatalog.group_by_category(%{
               "class_booking_requested" => 2,
               "class_slot_created" => 1
             })
  end

  test "only owners and admins may reset analytics, and no box can grant it" do
    assert AccessPolicy.can?(AccessPolicy.capabilities([:owner]), :reset_analytics)
    assert AccessPolicy.can?(AccessPolicy.capabilities([:admin]), :reset_analytics)

    for role <- [:coach, :front_desk, :accountant, :janitor, :member] do
      refute AccessPolicy.can?(AccessPolicy.capabilities([role]), :reset_analytics)
    end

    granted =
      AccessPolicy.capabilities([:front_desk],
        role_grants: %{"front_desk" => ["reset_analytics", "view_business_analytics"]}
      )

    assert AccessPolicy.can?(granted, :view_business_analytics)
    refute AccessPolicy.can?(granted, :reset_analytics)
  end
end
