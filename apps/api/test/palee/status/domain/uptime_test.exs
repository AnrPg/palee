defmodule Palee.Status.Domain.UptimeTest do
  use ExUnit.Case, async: true

  alias Palee.Status.Domain.Uptime

  test "window_days/1 clamps to 1..90" do
    assert Uptime.window_days(nil) == 90
    assert Uptime.window_days(7) == 7
    assert Uptime.window_days("30") == 30
    assert Uptime.window_days(0) == 1
    assert Uptime.window_days(500) == 90
    assert Uptime.window_days("x") == 90
  end

  test "history per component and day; degraded counts as up" do
    last = ~D[2026-11-02]

    samples = [
      %{
        component: "app",
        day: ~D[2026-11-01],
        total: 1440,
        operational: 1440,
        degraded: 0,
        down: 0
      },
      %{
        component: "app",
        day: ~D[2026-11-02],
        total: 600,
        operational: 500,
        degraded: 80,
        down: 20
      },
      %{
        component: "search",
        day: ~D[2026-11-02],
        total: 100,
        operational: 90,
        degraded: 0,
        down: 10
      }
    ]

    [app, search | rest] = Uptime.history(samples, last, 3)

    assert app.key == "app"
    assert Enum.map(app.days, & &1.date) == [~D[2026-10-31], ~D[2026-11-01], ~D[2026-11-02]]
    assert Enum.map(app.days, & &1.status) == ["no_data", "operational", "degraded"]
    assert Enum.at(app.days, 2).uptime_percent == 96.667
    assert app.uptime_percent == Float.round((2040 - 20) * 100 / 2040, 3)

    assert search.uptime_percent == 90.0
    assert List.last(search.days).status == "down"

    assert Enum.all?(rest, &(&1.uptime_percent == nil))
  end
end
