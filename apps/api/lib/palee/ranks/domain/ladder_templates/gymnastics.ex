defmodule Palee.Ranks.Domain.LadderTemplates.Gymnastics do
  @moduledoc "Template ladders: Gymnastics, acrobatics, calisthenics and parkour (ADR-400; sources in docs/research/rank-curricula-research-2026-11-03.md)."

  import Palee.Ranks.Domain.LadderTemplates.Build

  def all do
    [
      template(
        "gymnastics_levels",
        "Gymnastics levels 1-10",
        "gymnastics",
        "level",
        :palee,
        "Generic numbered levels (no skills; fill in your own)",
        [
          rank({"Level %{n}", 1}, nil, 0, [], []),
          rank({"Level %{n}", 2}, nil, 0, [], []),
          rank({"Level %{n}", 3}, nil, 0, [], []),
          rank({"Level %{n}", 4}, nil, 0, [], []),
          rank({"Level %{n}", 5}, nil, 0, [], []),
          rank({"Level %{n}", 6}, nil, 0, [], []),
          rank({"Level %{n}", 7}, nil, 0, [], []),
          rank({"Level %{n}", 8}, nil, 0, [], []),
          rank({"Level %{n}", 9}, nil, 0, [], []),
          rank({"Level %{n}", 10}, nil, 0, [], [])
        ]
      ),
      template(
        "artistic_women_levels",
        "Women's artistic gymnastics levels",
        "artistic_gymnastics",
        "level",
        :federation,
        "USA Gymnastics Development Program levels 1-10",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Forward roll and backward roll",
            "Bridge held 5 seconds",
            "Cartwheel",
            "Beam: walks and releve turns",
            "Bars: pullover with spot and front support",
            "Vault: straight jump onto mats"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Handstand held 2 seconds",
            "Backward roll to push-up position",
            "Bars: pullover and back hip circle",
            "Beam: cartwheel to handstand practice on low beam",
            "Vault: handstand flat-back onto mat stack"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Round-off",
            "Bridge kickover",
            "Bars: squat-on and cast to horizontal",
            "Beam: split leap and handstand",
            "Vault: front handspring onto mats"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Back walkover",
            "Front limber",
            "Bars: kip with spot and cast to handstand practice",
            "Beam: cartwheel",
            "Vault: front handspring over the table"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Back handspring",
            "Round-off back handspring",
            "Bars: kip cast to horizontal and clear hip circle",
            "Beam: back walkover",
            "Bars: long hang kip"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Back tuck",
            "Front tuck",
            "Bars: cast to 45 degrees above horizontal",
            "Beam: back handspring",
            "Optional routines with required elements"
          ]),
          rank({"Level %{n}", 7}, nil, 0, [], [
            "Round-off back handspring layout",
            "Bars: giant swing drills and flyaway dismount",
            "Beam: acro series of two elements",
            "Vault: Yamashita or handspring"
          ]),
          rank({"Level %{n}", 8}, nil, 0, [], [
            "Full twisting layout",
            "Bars: giant swings and release move drills",
            "Beam: salto element",
            "Vault: Tsukahara or round-off entry drills"
          ]),
          rank({"Level %{n}", 9}, nil, 0, [], [
            "Double twist or front layout full",
            "Bars: release move",
            "Beam: two-element acro series with a salto",
            "Vault: Yurchenko layout"
          ]),
          rank({"Level %{n}", 10}, nil, 0, [], [
            "Floor: D and E value skills in routine",
            "Bars: release and pirouetting elements",
            "Beam: complete optional routine to Level 10 rules",
            "Vault: Yurchenko full or harder"
          ])
        ]
      ),
      template(
        "artistic_women_xcel",
        "Xcel divisions (women's artistic)",
        "artistic_gymnastics",
        "level",
        :federation,
        "USA Gymnastics Xcel Bronze to Sapphire",
        [
          rank("Bronze", nil, 0, [], [
            "Cartwheel and handstand forward roll",
            "Bars: pullover and back hip circle",
            "Beam: leap and full turn on two feet",
            "Vault: handstand flat-back"
          ]),
          rank("Silver", nil, 0, [], [
            "Round-off and back walkover",
            "Bars: kip or cast with clear hip",
            "Beam: cartwheel or walkover",
            "Vault: front handspring onto mats"
          ]),
          rank("Gold", nil, 0, [], [
            "Round-off back handspring",
            "Bars: kip cast and squat-on or circle",
            "Beam: acro element and split leap 120 degrees",
            "Vault: front handspring over the table"
          ]),
          rank("Platinum", nil, 0, [], [
            "Back tuck in a pass",
            "Bars: six A and one B value parts",
            "Beam: acro series"
          ]),
          rank("Diamond", nil, 0, [], [
            "Layout or twisting salto",
            "Bars: five A and two B value parts",
            "Beam: salto or two-flight series"
          ]),
          rank("Sapphire", nil, 0, [], ["Harder value parts on every event", "Age 12 or older"])
        ]
      ),
      template(
        "artistic_men_levels",
        "Men's artistic gymnastics levels",
        "artistic_gymnastics",
        "level",
        :federation,
        "USA Gymnastics men's Development Program (6 apparatus)",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Forward and backward rolls",
            "Pommel: front support hold 10 seconds",
            "Rings: tuck hang and skin the cat",
            "Parallel bars: support walk",
            "High bar: hang and pullover"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Handstand forward roll and cartwheel",
            "Pommel: single leg circles on mushroom",
            "Rings: muscle-up drills with support hold",
            "High bar: cast and back hip circle"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Round-off and back handspring with spot",
            "Pommel: double leg circles on mushroom",
            "Parallel bars: swing in support and straddle dismount",
            "Vault: front handspring"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Back tuck and front tuck",
            "Rings: L-sit 2 seconds and swings",
            "High bar: kip and underswing dismount"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Pommel: circles on the pommel horse",
            "Parallel bars: peach basket drills",
            "High bar: giant swing drills"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Layout and full twist on floor",
            "Rings: back lever and support hold",
            "High bar: giant swings"
          ]),
          rank({"Level %{n}", 7}, nil, 0, [], [
            "Pommel: flairs or scissors",
            "Parallel bars: handstand and stutz",
            "Vault: handspring front tuck"
          ]),
          rank({"Level %{n}", 8}, nil, 0, [], [
            "Floor: double salto drills",
            "Rings: strength hold (cross or planche) drills",
            "High bar: release move drills"
          ]),
          rank({"Level %{n}", 9}, nil, 0, [], ["Floor: double back", "High bar: release move"]),
          rank({"Level %{n}", 10}, nil, 0, [], [
            "Optional routines to the men's code",
            "All six apparatus at competition level"
          ])
        ]
      ),
      template(
        "rhythmic_levels",
        "Rhythmic gymnastics levels",
        "rhythmic_gymnastics",
        "level",
        :federation,
        "USA Gymnastics Rhythmic Development Program levels 1-10",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Releve walks and balance on toes",
            "Pointed feet and straight-leg positions",
            "Rope: swings and skips forward",
            "Ball: rolls on the floor and bounces"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Passe balance for 2 seconds",
            "Front and side splits",
            "Rope: double turn swing and toss",
            "Ball: roll along the arms"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Pivot 360 degrees in passe",
            "Split leap and stag leap",
            "Floor routine to music",
            "Rope and ball routines"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Arabesque and attitude balances",
            "Back bend and walkover",
            "Hoop: rolls spins and tosses"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Ring leap and cossack jump",
            "Pivots of 720 degrees",
            "Ball: throw and catch with one hand",
            "Hoop: rotation around the hand and the body"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Clubs: mills and small circles",
            "Leg in hand balance (penche drills)",
            "Dynamic elements with rotation under a throw"
          ]),
          rank({"Level %{n}", 7}, nil, 0, [], [
            "Ribbon: spirals and snakes",
            "Clubs: asymmetric movements and throws",
            "Two apparatus routines with difficulty"
          ]),
          rank({"Level %{n}", 8}, nil, 0, [], [
            "Four routines: floor and three apparatus",
            "Penche and ring balances",
            "Apparatus masteries (risk elements)"
          ]),
          rank({"Level %{n}", 9}, nil, 0, [], [
            "Routines with hoop ball clubs and ribbon",
            "Fouette and illusion pivots"
          ]),
          rank({"Level %{n}", 10}, nil, 0, [], [
            "Routines under the FIG Code of Points",
            "Body and apparatus difficulties at junior or senior level"
          ])
        ]
      ),
      template(
        "trampoline_awards",
        "Trampoline awards 1-15",
        "trampoline_tumbling",
        "level",
        :federation,
        "British Gymnastics trampoline proficiency awards",
        [
          rank({"Award %{n}", 1}, nil, 0, [], [
            "Straight jump with controlled stop",
            "Tuck jump",
            "Straddle and pike jumps"
          ]),
          rank({"Award %{n}", 2}, nil, 0, [], [
            "Seat drop",
            "Half twist jump",
            "Hands and knees drop"
          ]),
          rank({"Award %{n}", 3}, nil, 0, [], [
            "Full twist jump",
            "Seat drop half twist to seat",
            "Five-move routine"
          ]),
          rank({"Award %{n}", 4}, nil, 0, [], ["Front drop", "Back drop", "Swivel hips"]),
          rank({"Award %{n}", 5}, nil, 0, [], [
            "Half twist to front drop",
            "Back drop half twist to feet",
            "Ten-move routine"
          ]),
          rank({"Award %{n}", 6}, nil, 0, [], [
            "Front somersault tucked",
            "Back drop to front drop (turnover)"
          ]),
          rank({"Award %{n}", 7}, nil, 0, [], ["Back somersault tucked", "Cradle"]),
          rank({"Award %{n}", 8}, nil, 0, [], ["Back somersault piked", "Barani tucked"]),
          rank({"Award %{n}", 9}, nil, 0, [], [
            "Back somersault straight",
            "Barani piked",
            "Ten-move routine with somersaults"
          ]),
          rank({"Award %{n}", 10}, nil, 0, [], [
            "Back somersault with full twist",
            "Barani straight"
          ]),
          rank({"Award %{n}", 11}, nil, 0, [], [
            "Front somersault piked and tuck with three half twists",
            "Ball-out"
          ]),
          rank({"Award %{n}", 12}, nil, 0, [], [
            "Barani straight with five somersault shapes",
            "Rudolph (front with one and a half twists)"
          ]),
          rank({"Award %{n}", 13}, nil, 0, [], [
            "Double back somersault tucked",
            "Double twisting back"
          ]),
          rank({"Award %{n}", 14}, nil, 0, [], [
            "Double front or barani-out",
            "Voluntary routine with doubles"
          ]),
          rank({"Award %{n}", 15}, nil, 0, [], [
            "Competition voluntary routine at national grade",
            "Triple-twisting or twisting doubles"
          ])
        ]
      ),
      template(
        "tumbling_levels",
        "Tumbling levels",
        "trampoline_tumbling",
        "level",
        :federation,
        "USA Gymnastics trampoline and tumbling levels 1-10",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Forward roll and backward roll",
            "Cartwheel and handstand"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], ["Round-off", "Bridge kickover"]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Back walkover and front walkover",
            "Round-off rebound"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], ["Back handspring", "Front handspring"]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Round-off back handspring back tuck",
            "Front tuck"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], ["Series of back handsprings", "Back layout"]),
          rank({"Level %{n}", 7}, nil, 0, [], ["Whip back", "Back full twist"]),
          rank({"Level %{n}", 8}, nil, 0, [], ["Double full", "Front layout"]),
          rank({"Level %{n}", 9}, nil, 0, [], ["Double back tucked", "Passes of eight elements"]),
          rank({"Level %{n}", 10}, nil, 0, [], [
            "Double back piked or full-in",
            "Competition passes to the code"
          ])
        ]
      ),
      template(
        "acrobatics_levels",
        "Acrobatics levels",
        "acrobatics",
        "level",
        :palee,
        "Acrobatic gymnastics and hand balancing (USA Gymnastics acro and circus schools)",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Handstand against the wall 30 seconds",
            "Bridge and splits",
            "Base and flyer safety rules"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Freestanding handstand 5 seconds",
            "Pair balances: bird and throne",
            "Cartwheel and round-off"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Handstand 15 seconds and pirouette walk",
            "Pair balances: shoulder stand and star",
            "Back walkover"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Press to handstand",
            "Hand-to-hand drills with a spotter",
            "Simple pair tempo element (toss to catch)"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "One-arm handstand drills",
            "Balance routine of three elements",
            "Tempo routine with a back salto toss"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Hand-to-hand hold 3 seconds",
            "Group pyramid of three",
            "Combined routine to music"
          ])
        ]
      ),
      template(
        "crossfit_gymnastics",
        "CrossFit gymnastics skills",
        "gymnastics",
        "level",
        :palee,
        "Skill progressions used in CrossFit gymnastics courses",
        [
          rank("Foundations", nil, 0, [], [
            "Hollow hold 30 seconds and arch hold 30 seconds",
            "Dead hang 30 seconds",
            "10 push-ups to full depth",
            "Box jump and step-down"
          ]),
          rank("Strict strength", nil, 0, [], [
            "5 strict pull-ups",
            "5 strict ring dips",
            "5 strict toes-to-bar or hanging knee raises",
            "Wall walk to nose and wall"
          ]),
          rank("Kipping", nil, 0, [], [
            "Kip swing 10 in a row",
            "Kipping pull-ups 10 unbroken",
            "Kipping toes-to-bar 10 unbroken",
            "Handstand hold against the wall 30 seconds"
          ]),
          rank("Rx skills", nil, 0, [], [
            "Chest-to-bar pull-ups 10 unbroken",
            "Kipping handstand push-ups 5 unbroken",
            "Double-unders 50 unbroken",
            "Rope climb 4.5 metres with legs"
          ]),
          rank("Advanced", nil, 0, [], [
            "Bar muscle-ups 5 unbroken",
            "Ring muscle-up",
            "Handstand walk 15 metres",
            "Legless rope climb"
          ]),
          rank("Elite", nil, 0, [], [
            "Ring muscle-ups 5 unbroken",
            "Strict handstand push-ups 10 unbroken",
            "Handstand walk over obstacles",
            "Deficit handstand push-ups"
          ])
        ]
      ),
      template(
        "calisthenics_levels",
        "Calisthenics levels",
        "calisthenics",
        "level",
        :palee,
        "Street workout strength progressions",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "10 push-ups and 20 bodyweight squats",
            "Dead hang 30 seconds and scapular pulls",
            "Plank 60 seconds and hollow hold 30 seconds"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "5 pull-ups",
            "10 dips on parallel bars",
            "20 push-ups",
            "Tuck L-sit 10 seconds"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "10 pull-ups and 20 dips",
            "L-sit 10 seconds",
            "Wall handstand 30 seconds",
            "Tuck front lever 10 seconds",
            "5 pistol squats per leg (assisted allowed)"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Muscle-up on the bar",
            "Freestanding handstand 10 seconds",
            "Advanced tuck front lever 10 seconds",
            "Tuck planche 5 seconds",
            "Human flag drills"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "5 muscle-ups",
            "Straddle front lever 5 seconds",
            "Straddle planche drills",
            "Human flag 5 seconds",
            "Handstand push-up against the wall"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Full front lever 5 seconds",
            "Straddle planche 5 seconds",
            "Freestanding handstand push-up",
            "One-arm pull-up drills"
          ])
        ]
      ),
      template(
        "street_workout_freestyle",
        "Street workout freestyle",
        "calisthenics",
        "level",
        :palee,
        "Freestyle bar skills (statics dynamics and power moves)",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Front and back support on the bar",
            "Swing with hollow and arch",
            "Pullover"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Muscle-up",
            "Back hip circle",
            "180 degree switch grip in swing"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Underswing dismount",
            "Bar spin (360 degree spin over the bar)",
            "Kip-up on the bar"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Giant swing with straps or spotter",
            "180 release and regrab",
            "Combo of three dynamic elements"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Unassisted giant swings",
            "360 release or flip dismount",
            "Freestyle routine of 60 seconds"
          ])
        ]
      ),
      template(
        "parkour_levels",
        "Parkour levels",
        "parkour",
        "level",
        :palee,
        "Basic to expert technique tiers used by parkour schools",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Safe landing and roll",
            "Quadrupedal movement 20 metres",
            "Safety vault and step vault",
            "Balance walk on a rail"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Precision jump to a line",
            "Lazy vault and speed vault",
            "Tic-tac off a wall",
            "Cat hang (arm jump hold)"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Kong vault",
            "Cat leap from a standing jump",
            "Wall run and climb-up",
            "Precision jump of 2 metres"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Dash vault and kash vault",
            "Kong to precision",
            "Running cat leap",
            "Underbar"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Double kong",
            "Turn vault and laché",
            "Flowing line of six movements"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Long precision and running precision",
            "Route planning and risk assessment",
            "Coaches a beginner line"
          ])
        ]
      ),
      template(
        "freerunning_levels",
        "Freerunning levels",
        "parkour",
        "level",
        :palee,
        "Acrobatic freerunning progression",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Forward roll on hard ground",
            "Cartwheel and round-off"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Front flip on soft ground",
            "Side flip drills (aerial)"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], ["Back flip", "Wall flip (wall spin drills)"]),
          rank({"Level %{n}", 4}, nil, 0, [], ["Webster", "Gainer", "Palm flip"]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Cork or double leg",
            "Flip combinations on obstacles",
            "Freestyle line with three flips"
          ])
        ]
      )
    ]
  end
end
