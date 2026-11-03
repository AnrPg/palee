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
        "Generic numbered levels (add your own skills)",
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
            "Round-off back handspring",
            "Bars: glide kip and cast to horizontal",
            "Bars: long hang kip and back hip circle",
            "Beam: cartwheel",
            "Vault: front handspring over the table"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Round-off back handspring back tuck",
            "Front tuck or aerial",
            "Bars: kip cast above horizontal and clear hip circle",
            "Bars: flyaway dismount",
            "Beam: back walkover or back handspring",
            "Beam: back tuck dismount"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Optional routines with required elements",
            "Bars: cast to 45 degrees above horizontal",
            "Back layout"
          ]),
          rank({"Level %{n}", 7}, nil, 0, [], [
            "Round-off back handspring layout",
            "Bars: giant swing drills",
            "Beam: acro series of two elements",
            "Vault: handspring (Yamashita optional)"
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
            "Every event meets the Platinum special requirements",
            "Beam: acro series"
          ]),
          rank("Diamond", nil, 0, [], [
            "Layout or twisting salto",
            "Every event meets the Diamond special requirements",
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
        "USA Gymnastics men's Development Program",
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
        "USA Gymnastics rhythmic levels 3-8 then FIG Junior and Senior",
        [
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Age 6 or older",
            "Releve walks and passe balance",
            "Split leap and stag leap",
            "Floor routine to music",
            "One apparatus routine (rope or ball)"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Pivot 360 degrees in passe",
            "Arabesque and attitude balances",
            "Group floor routine",
            "Two apparatus routines"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Age 7 or older",
            "Floor and three apparatus routines",
            "Hoop: rolls spins and tosses",
            "Ball: throw and catch with one hand"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Age 8 or older",
            "Pivots of 720 degrees",
            "Clubs: mills and small circles",
            "Ring leap and cossack jump"
          ]),
          rank({"Level %{n}", 7}, nil, 0, [], [
            "Age 9 or older",
            "Ribbon: spirals and snakes",
            "Leg in hand balance (penche drills)",
            "Dynamic elements with rotation under a throw"
          ]),
          rank({"Level %{n}", 8}, nil, 0, [], [
            "Age 10 or older",
            "Penche and ring balances",
            "Apparatus masteries (risk elements)"
          ]),
          rank("Junior", nil, 0, [], [
            "Age 13 or older (FIG junior)",
            "Routines with hoop ball clubs and ribbon",
            "Fouette and illusion pivots"
          ]),
          rank("Senior", nil, 0, [], [
            "Age 16 or older (FIG senior)",
            "Routines under the FIG Code of Points"
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
            "Waits their turn and behaves safely around the trampoline",
            "Mounts and dismounts from the centre",
            "Bounces lying sitting or on hands and knees"
          ]),
          rank({"Award %{n}", 2}, nil, 0, [], [
            "Seated bounce with arm movements",
            "Bounces a set number of times and stops",
            "Quarter turn upright",
            "Seat drop without returning to feet",
            "Star position"
          ]),
          rank({"Award %{n}", 3}, nil, 0, [], [
            "Straight jumps using the arms",
            "Tuck jump",
            "Astride jump and star jump",
            "Half twist jump"
          ]),
          rank({"Award %{n}", 4}, nil, 0, [], [
            "Tuck jump touching below the knees",
            "Straddle jump and split jump",
            "Seat drop returning to feet",
            "Two half twist jumps linked"
          ]),
          rank({"Award %{n}", 5}, nil, 0, [], [
            "Five straight jumps then stop for 3 seconds",
            "Piked straddle jump",
            "Front landing and back landing on a mat",
            "Seat drop to feet with half twist",
            "Routine: straddle seat to feet tuck half twist straight"
          ]),
          rank({"Award %{n}", 6}, nil, 0, [], [
            "Seat landing half twist to feet",
            "Full twist jump",
            "Front landing to feet",
            "Pike jump",
            "Ten-move routine with seat landings and twists"
          ]),
          rank({"Award %{n}", 7}, nil, 0, [], [
            "Swivel hips (seat half twist to seat)",
            "Back landing to feet",
            "Hands and knees forward turnover to back landing",
            "Seat landing to feet then front landing to feet"
          ]),
          rank({"Award %{n}", 8}, nil, 0, [], [
            "Seat landing to front landing to feet",
            "Half twist to front landing and to back landing",
            "Front and back landing with half twist to feet",
            "Five back bounces"
          ]),
          rank({"Award %{n}", 9}, nil, 0, [], [
            "Piked and straight front and back landings",
            "Front landing to back landing and back to front",
            "Forward three-quarter turnover to back landing",
            "Seat landing full twist to seat (roller)"
          ]),
          rank({"Award %{n}", 10}, nil, 0, [], [
            "Front or back somersault tucked",
            "Back landing back pullover to feet",
            "Front landing half turntable",
            "Ten-move routine with one somersault"
          ]),
          rank({"Award %{n}", 11}, nil, 0, [], [
            "Front somersault piked",
            "Back somersault tucked and back somersault straight or piked",
            "Three-quarter front somersault straight to back landing",
            "Routine with three somersaults",
            "Floor conditioning: 20 crunches and 20 dorsal raises"
          ]),
          rank({"Award %{n}", 12}, nil, 0, [], [
            "Barani with straight legs",
            "Crash dive straight",
            "Back somersault tucked then front somersault piked",
            "Routine with four somersaults including a barani"
          ]),
          rank({"Award %{n}", 13}, nil, 0, [], [
            "Barani tucked and piked",
            "Back somersault then barani in the same shape",
            "Crash dive to bounce roll",
            "Routine with six somersaults"
          ]),
          rank({"Award %{n}", 14}, nil, 0, [], [
            "Barani straight",
            "Back somersault with half twist",
            "Full twisting front somersault",
            "Crash dive to ball out",
            "Routine with seven somersaults"
          ]),
          rank({"Award %{n}", 15}, nil, 0, [], [
            "Crash dive to ball-out barani",
            "Full twisting back somersault straight",
            "Rudi (front with one and a half twists)",
            "Cody from a front landing",
            "Ten-somersault routine with tariff 5.6 or more"
          ])
        ]
      ),
      template(
        "tumbling_levels",
        "Tumbling levels",
        "trampoline_tumbling",
        "level",
        :federation,
        "USA Gymnastics tumbling levels 1-10",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Forward roll and backward roll",
            "Cartwheel",
            "Straight jump with stuck landing"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Handstand forward roll",
            "Round-off",
            "Back roll to push-up"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Round-off back handspring rebound",
            "Front handspring"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], ["Round-off and two to four back handsprings"]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Round-off back handsprings back tuck",
            "Passes of eight elements"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], ["Back pike or tuck finish", "Whip back"]),
          rank({"Level %{n}", 7}, nil, 0, [], [
            "Whip backs and back handsprings in series",
            "Back layout"
          ]),
          rank({"Level %{n}", 8}, nil, 0, [], ["Back somersault with a full twist (360 degrees)"]),
          rank({"Level %{n}", 9}, nil, 0, [], [
            "Back full in elements two to seven",
            "No double somersault before the last element"
          ]),
          rank({"Level %{n}", 10}, nil, 0, [], [
            "A double somersault in the pass",
            "Double back tucked or piked"
          ])
        ]
      ),
      template(
        "acrobatics_levels",
        "Acrobatics levels",
        "acrobatics",
        "level",
        :palee,
        "Palee levels from acro gymnastics and hand balancing",
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
        "Palee skill progressions for CrossFit gymnastics",
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
        "Palee street workout strength progressions",
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
        "Palee freestyle bar progression",
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
        "Palee technique tiers used by parkour schools",
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
        "Palee acrobatic freerunning progression",
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
