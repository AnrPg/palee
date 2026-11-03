defmodule Palee.Ranks.Domain.LadderTemplates.Outdoor do
  @moduledoc "Template ladders: Skateboarding and climbing (ADR-400; sources in docs/research/rank-curricula-research-2026-11-03.md)."

  import Palee.Ranks.Domain.LadderTemplates.Build

  def all do
    [
      template(
        "skateboarding_levels",
        "Skateboarding levels",
        "skateboarding",
        "level",
        :palee,
        "Palee levels from Skateboard GB beginner awards and common progression",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Stance (regular or goofy) and pushing",
            "Stopping with the foot and the tail",
            "Carving turns",
            "Falling safely with pads"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Kickturns",
            "Tic-tacs",
            "Roll up and down a small ramp"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Drop in on a mini ramp",
            "Ollie on flat",
            "Manual 2 metres"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Ollie onto a curb",
            "50-50 grind",
            "Frontside and backside 180"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Kickflip",
            "Pop shove-it",
            "Rock to fakie on a ramp"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Boardslide on a rail",
            "Heelflip or varial flip",
            "Line of three tricks"
          ])
        ]
      ),
      template(
        "climbing_nicas",
        "Indoor climbing levels",
        "climbing_bouldering",
        "level",
        :federation,
        "NICAS levels 1-5 (UK national indoor climbing scheme)",
        [
          rank("Foundation climber", nil, 0, [], [
            "Fits a harness and helmet correctly",
            "Figure-eight knot checked by a partner",
            "Climbs a top-rope route and is lowered"
          ]),
          rank("Top-rope climber", nil, 0, [], [
            "Belays top-rope with an assisted device",
            "Climbs grade 4 routes cleanly",
            "Safe bouldering falls"
          ]),
          rank("Technical climber", nil, 0, [], [
            "Footwork: edging and smearing",
            "Flagging and drop knee",
            "Climbs grade 5 routes"
          ]),
          rank("Lead climber", nil, 0, [], [
            "Lead climbs and clips in sequence",
            "Lead belays with dynamic catches",
            "Takes practice lead falls"
          ]),
          rank("Advanced climber", nil, 0, [], [
            "Climbs grade 6a or harder on lead",
            "Plans training and route reading",
            "Takes part in a competition"
          ])
        ]
      ),
      template(
        "bouldering_grades",
        "Bouldering grades",
        "climbing_bouldering",
        "level",
        :federation,
        "V-scale grades (Fontainebleau in brackets)",
        [
          rank("V0 (4)", nil, 0, [], ["Tops three different V0 problems"]),
          rank("V1 (5)", nil, 0, [], ["Tops three different V1 problems"]),
          rank("V2 (5+)", nil, 0, [], ["Tops three different V2 problems"]),
          rank("V3 (6A)", nil, 0, [], [
            "Tops three different V3 problems",
            "Heel hooks and toe hooks"
          ]),
          rank("V4 (6B)", nil, 0, [], [
            "Tops three different V4 problems",
            "Dynos and coordination moves"
          ]),
          rank("V5 (6C)", nil, 0, [], ["Tops three different V5 problems"]),
          rank("V6 (7A)", nil, 0, [], [
            "Tops three different V6 problems",
            "Campus and fingerboard basics with care"
          ]),
          rank("V7 (7A+)", nil, 0, [], ["Tops three different V7 problems"]),
          rank("V8 (7B)", nil, 0, [], ["Tops three different V8 problems"])
        ]
      )
    ]
  end
end
