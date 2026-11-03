defmodule PaleeWeb.ControllerSpecsGuardTest do
  # open_api_spex's own `use OpenApiSpex.ControllerSpecs` bakes every
  # operation of a controller into every clause (N² module literals), which
  # OOM-killed the API at 1 GiB. Every controller must use
  # PaleeWeb.ControllerSpecs instead.
  use ExUnit.Case, async: true

  test "no module uses OpenApiSpex.ControllerSpecs directly" do
    offenders =
      Path.wildcard(Path.expand("../../lib/**/*.ex", __DIR__))
      |> Enum.filter(&(File.read!(&1) =~ ~r/use\s+OpenApiSpex\.ControllerSpecs/))
      |> Enum.map(&Path.relative_to(&1, Path.expand("../..", __DIR__)))

    assert offenders == []
  end
end
