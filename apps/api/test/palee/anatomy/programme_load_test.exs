defmodule Palee.Anatomy.ProgrammeLoadTest do
  @moduledoc "ADR-670 «Φορτίο προγράμματος» (pure)."
  use ExUnit.Case, async: true

  alias Palee.Anatomy

  test "rolls heads up to groups, counts each WOD once with its strongest role, most WODs first" do
    monday = ~D[2026-11-16]
    tuesday = ~D[2026-11-17]

    load =
      Anatomy.programme_load([
        %{
          on: monday,
          muscles: [
            %{id: "quadriceps", role: "primary"},
            %{id: "rectus-femoris", role: :secondary},
            %{id: "gluteus-maximus", role: "secondary"},
            %{id: "unknown-muscle", role: "primary"},
            %{id: "thighs", role: "primary"}
          ]
        },
        %{on: tuesday, muscles: [%{id: "vastus-lateralis", role: "stabilizer"}]},
        %{on: tuesday, muscles: [%{id: "glutes", role: "bogus"}]},
        %{on: tuesday, muscles: []}
      ])

    assert [quadriceps, glutes] = load

    assert quadriceps == %{
             id: "quadriceps",
             wods: 2,
             primary: 1,
             secondary: 0,
             stabilizer: 1,
             dates: [monday, tuesday]
           }

    assert glutes == %{
             id: "glutes",
             wods: 1,
             primary: 0,
             secondary: 1,
             stabilizer: 0,
             dates: [monday]
           }
  end

  test "nothing programmed, nothing loaded" do
    assert Anatomy.programme_load([]) == []
  end
end
