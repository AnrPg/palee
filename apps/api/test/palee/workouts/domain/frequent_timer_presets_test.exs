defmodule Palee.Workouts.Domain.FrequentTimerPresetsTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.FrequentTimerPresets

  # Shared with the web client (canonicalTimerPreset), so both sides agree.
  @fixture_path Path.expand(
                  "../../../../../web/src/lib/timer-preset-canonical-fixtures.json",
                  __DIR__
                )
  @external_resource @fixture_path

  test "canonical forms match the web client's" do
    for %{"preset" => preset, "canonical" => canonical} <-
          @fixture_path |> File.read!() |> Jason.decode!() |> Map.fetch!("cases") do
      assert FrequentTimerPresets.canonical(preset) == canonical, inspect(preset)
    end
  end

  defp usage(preset, uses, at \\ ~N[2026-11-01 10:00:00]),
    do: %{preset: preset, uses: uses, last_used_at: at}

  defp formats(chips), do: Enum.map(chips, &{&1.source, &1.preset})

  test "no history: the stock chips, AMRAP 12, EMOM 10 and For Time cap 12" do
    assert formats(FrequentTimerPresets.choose([], [])) == [
             {:stock, %{"format" => "amrap", "duration_seconds" => 720}},
             {:stock, %{"format" => "emom", "interval_seconds" => 60, "rounds" => 10}},
             {:stock, %{"format" => "for_time", "duration_seconds" => 720}}
           ]
  end

  test "the author's most used first, topped up by the gym, then stock, never twice" do
    emom4 = %{"format" => "emom", "interval_seconds" => 60, "rounds" => 4}
    amrap10 = %{"format" => "amrap", "duration_seconds" => 600}

    author = [usage(amrap10, 1), usage(emom4, 3)]
    gym = [usage(emom4, 9), usage(%{"format" => "amrap", "duration_seconds" => 720}, 2)]

    assert formats(FrequentTimerPresets.choose(author, gym)) == [
             {:author, emom4},
             {:author, amrap10},
             {:gym, %{"format" => "amrap", "duration_seconds" => 720}}
           ]
  end

  test "«No time» and broken presets never count" do
    author = [
      usage(%{"format" => "untimed"}, 50),
      usage(%{"format" => "rocket"}, 9),
      usage(nil, 3)
    ]

    assert Enum.all?(FrequentTimerPresets.choose(author, []), &(&1.source == :stock))
  end

  test "the same timer written two ways is one chip, its uses added up" do
    author = [
      usage(%{"format" => "emom", "rounds" => nil, "rest_seconds" => 20}, 2),
      usage(%{"format" => "emom", "interval_seconds" => 60, "rounds" => 10}, 1),
      usage(%{"format" => "tabata"}, 2)
    ]

    assert [first, second | _rest] = FrequentTimerPresets.choose(author, [])
    assert first.preset == %{"format" => "emom", "interval_seconds" => 60, "rounds" => 10}
    assert first.uses == 3

    assert second.preset == %{
             "format" => "tabata",
             "work_seconds" => 20,
             "rest_seconds" => 10,
             "rounds" => 8
           }
  end

  test "ties go to the timer used last" do
    old = usage(%{"format" => "amrap", "duration_seconds" => 600}, 2, ~N[2026-10-01 10:00:00])
    new = usage(%{"format" => "amrap", "duration_seconds" => 1200}, 2, ~N[2026-11-05 10:00:00])

    assert [%{preset: %{"duration_seconds" => 1200}}, %{preset: %{"duration_seconds" => 600}} | _] =
             FrequentTimerPresets.choose([old, new], [])
  end
end
