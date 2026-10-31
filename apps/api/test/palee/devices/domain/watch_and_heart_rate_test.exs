defmodule Palee.Devices.Domain.WatchAndHeartRateTest do
  @moduledoc "ADR-375: the watch contract and heart-rate batches."

  use ExUnit.Case, async: true

  alias Palee.Devices.Domain.{HeartRate, WatchContract}

  describe "WatchContract" do
    test "speaks version 1 and knows when a watch app must update" do
      assert WatchContract.version() == 1
      assert WatchContract.supported?(1)
      refute WatchContract.supported?(0)
      refute WatchContract.supported?(2)
      refute WatchContract.supported?("1")
    end

    test "merges settings and checks them" do
      assert {:ok, %{"haptics" => false, "show_heart_rate" => true, "max_hr" => 190}} =
               WatchContract.merge_settings(nil, %{haptics: false, max_hr: 190})

      for bad <- [%{haptics: "yes"}, %{max_hr: 300}, %{unknown: true}] do
        assert {:error, :invalid_watch_settings} = WatchContract.merge_settings(%{}, bad)
      end
    end

    test "builds the compact plan the watch runs" do
      execution = %{
        id: "e1",
        workout_title: "Fran",
        status: :active,
        current_segment_index: 0,
        lock_version: 3,
        total_elapsed_ms: 1000,
        paused_elapsed_ms: 0,
        segment_started_at_utc: nil
      }

      segments = [
        %{
          kind: :countup,
          phase: "work",
          duration_seconds: 600,
          section_name: "21-15-9",
          label: "For time",
          exercises: [
            %{name: "Thruster", prescription_value: 21, prescription_unit: "reps"},
            %{"name" => "Pull-up"},
            %{name: ""},
            %{name: "Run"}
          ]
        }
      ]

      plan = WatchContract.plan(execution, segments, [%{key: "0:work:1:0", section_ordinal: 0, phase: "work", round: 1, at_ms: 90_000, extra: 1}], %{"show_pace" => true})

      assert plan.contract_version == 1
      assert plan.status == "active"
      assert plan.progress.lock_version == 3
      assert [%{index: 0, kind: "countup", movements: movements}] = plan.segments
      assert Enum.map(movements, & &1.name) == ["Thruster", "Pull-up"]
      assert [%{at_ms: 90_000} = point] = plan.pace
      refute Map.has_key?(point, :extra)
      assert plan.commands == ~w(next round pause resume finish)

      assert WatchContract.plan(execution, segments, [%{key: "k", section_ordinal: 0, phase: "work", round: 1, at_ms: 1}], %{"show_pace" => false}).pace == []
    end
  end

  describe "HeartRate" do
    test "casts numbered batches and refuses bad ones" do
      batch = %{"sequence" => 0, "started_offset_ms" => 0, "interval_ms" => 5000, "bpm" => [100, 110]}
      assert {:ok, [%{sequence: 0, platform: "wear_os"}]} = HeartRate.cast_batches([batch, batch], "wear_os")

      for bad <- [
            [],
            [%{batch | "interval_ms" => 500}],
            [%{batch | "bpm" => []}],
            [%{batch | "bpm" => List.duplicate(100, 721)}],
            [%{batch | "sequence" => -1}],
            List.duplicate(batch, 31)
          ] do
        assert {:error, :invalid_heart_rate_batch} = HeartRate.cast_batches(bad, "wear_os")
      end

      assert {:error, :invalid_heart_rate_batch} = HeartRate.cast_batches([batch], "fitbit")
    end

    test "summarises: averages, per section, zones only with a maximum, noise dropped" do
      batches = [
        %{started_offset_ms: 0, interval_ms: 5000, bpm: [100, 120, 0, 140]},
        %{started_offset_ms: 20_000, interval_ms: 5000, bpm: [160, 180]}
      ]

      windows = HeartRate.section_windows(%{1 => 10_000, 0 => 15_000})
      assert windows == [{0, 0, 15_000}, {1, 15_000, 25_000}]

      summary = HeartRate.summary(batches, windows, 200)
      assert summary.samples == 5
      assert summary.average_bpm == 140
      assert summary.max_bpm == 180
      assert summary.min_bpm == 100

      assert [%{section_ordinal: 0, average_bpm: 110}, %{section_ordinal: 1, average_bpm: 160}] =
               summary.sections

      assert Enum.find(summary.zones, &(&1.zone == 5)).ms == 5000
      assert Enum.find(summary.zones, &(&1.zone == 1)).ms == 5000
      assert HeartRate.summary(batches, [], nil).zones == []
      assert HeartRate.summary([], [], nil).average_bpm == nil
    end
  end
end
