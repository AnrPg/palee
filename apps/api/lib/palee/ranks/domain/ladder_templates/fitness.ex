defmodule Palee.Ranks.Domain.LadderTemplates.Fitness do
  @moduledoc "Template ladders: Functional fitness, strength, swimming and yoga (ADR-400; sources in docs/research/rank-curricula-research-2026-11-03.md)."

  import Palee.Ranks.Domain.LadderTemplates.Build

  def all do
    [
      template(
        "crossfit_levels",
        "CrossFit levels",
        "crossfit",
        "level",
        :palee,
        "Palee levels from CrossFit scaling and benchmarks",
        [
          rank("Foundations", nil, 0, [], [
            "Air squat to full depth with a neutral spine",
            "Deadlift and press with PVC or empty bar",
            "Hollow hold 30 seconds",
            "Knows the class whiteboard and scaling"
          ]),
          rank("Scaled", nil, 0, [], [
            "Front squat and push press with load",
            "Ring rows and banded pull-ups",
            "2000 metre row under 10 minutes",
            "Finishes Cindy scaled"
          ]),
          rank("Intermediate", nil, 0, [], [
            "Power clean and power snatch with good form",
            "5 strict pull-ups and 10 push-ups unbroken",
            "Single-unders 100 and double-under attempts",
            "Back squat 1 times bodyweight"
          ]),
          rank("Rx", nil, 0, [], [
            "Kipping pull-ups and toes-to-bar",
            "Double-unders 30 unbroken",
            "Fran and Grace at Rx loads",
            "Back squat 1.5 times bodyweight (men) or 1.2 (women)"
          ]),
          rank("Rx+", nil, 0, [], [
            "Bar and ring muscle-ups",
            "Handstand push-ups and walks",
            "Squat snatch and squat clean at Rx loads",
            "Fran under 5 minutes"
          ]),
          rank("Competitor", nil, 0, [], [
            "Open workouts at Rx with a top 25 percent finish",
            "Deadlift 2 times bodyweight",
            "Pacing plan for long chippers"
          ])
        ]
      ),
      template(
        "metcon_levels",
        "Metcon engine levels",
        "hiit",
        "level",
        :palee,
        "Palee benchmarks for conditioning classes",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Finishes a 12-minute AMRAP at a steady pace",
            "500 metre row under 2:30",
            "Knows how to scale a movement"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "EMOM of 20 minutes without missing a minute",
            "1 km run under 5:30",
            "50 burpees under 5 minutes"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "2000 metre row under 8:30",
            "Holds pace over 30-minute chippers",
            "Assault bike 50 calories under 4 minutes"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "5 km run under 25 minutes",
            "Intervals at threshold with even splits",
            "100 burpees under 9 minutes"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "2000 metre row under 7:30",
            "Murph or a 45-minute hero WOD",
            "Plans and logs their own pacing"
          ])
        ]
      ),
      template(
        "hyrox_divisions",
        "HYROX divisions",
        "hyrox",
        "level",
        :federation,
        "HYROX race divisions (Open Pro Elite 15)",
        [
          rank("Relay ready", nil, 0, [], [
            "Runs 1 km four times with recovery",
            "Each of the eight stations at Open load"
          ]),
          rank("Doubles", nil, 0, [], [
            "Full simulation with a partner (split stations)",
            "Sled push and sled pull technique",
            "100 wall balls with partner swaps"
          ]),
          rank("Open", nil, 0, [], [
            "8 km of running with eight stations alone",
            "1000 metre SkiErg and 1000 metre row at steady pace",
            "80 metre burpee broad jumps",
            "100 metre sandbag lunges and 100 wall balls"
          ]),
          rank("Pro", nil, 0, [], [
            "Full simulation at Pro loads",
            "Compromised running at race pace",
            "Race plan with target splits per station"
          ]),
          rank("Elite 15", nil, 0, [], [
            "Qualifies through a Pro race result",
            "Season plan with peaking"
          ])
        ]
      ),
      template(
        "weightlifting_classes",
        "Weightlifting classes",
        "olympic_lifting",
        "level",
        :federation,
        "Sports classification (Class III to Master of Sport) by bodyweight tables",
        [
          rank("Technique", nil, 0, [], [
            "Snatch and clean with PVC from the hang",
            "Overhead squat to full depth",
            "Front squat with elbows high"
          ]),
          rank("Class III", nil, 0, [], [
            "Full snatch and clean and jerk from the floor",
            "Total meets the federation Class III standard",
            "Knows competition rules and the three attempts"
          ]),
          rank("Class II", nil, 0, [], [
            "Split or power jerk with a stable catch",
            "Total meets the Class II standard"
          ]),
          rank("Class I", nil, 0, [], [
            "Total meets the Class I standard",
            "Competes in an official meet"
          ]),
          rank("Candidate Master of Sport", nil, 0, [], [
            "Total meets the CMS standard at an official meet"
          ]),
          rank("Master of Sport", nil, 0, [], ["Total meets the MS standard at a national meet"])
        ]
      ),
      template(
        "powerlifting_levels",
        "Powerlifting levels",
        "powerlifting",
        "level",
        :palee,
        "Palee strength standards (bodyweight multiples)",
        [
          rank("Beginner", nil, 0, [], [
            "Squat deadlift and bench press to competition depth with empty bar",
            "Bracing and the valsalva technique"
          ]),
          rank("Novice", nil, 0, [], [
            "Squat 1 times bodyweight",
            "Bench press 0.75 times bodyweight",
            "Deadlift 1.25 times bodyweight"
          ]),
          rank("Intermediate", nil, 0, [], [
            "Squat 1.5 times bodyweight",
            "Bench press 1 times bodyweight",
            "Deadlift 1.75 times bodyweight",
            "Follows a periodised programme"
          ]),
          rank("Advanced", nil, 0, [], [
            "Squat 2 times bodyweight",
            "Bench press 1.35 times bodyweight",
            "Deadlift 2.4 times bodyweight",
            "Competes under IPF rules"
          ]),
          rank("Elite", nil, 0, [], [
            "Squat 2.5 times bodyweight",
            "Deadlift 3 times bodyweight",
            "National-level total"
          ])
        ]
      ),
      template(
        "swim_stages",
        "Learn to swim stages",
        "swimming",
        "level",
        :federation,
        "Swim England Learn to Swim stages 1-7",
        [
          rank({"Stage %{n}", 1}, nil, 0, [], [
            "Enters and exits the water safely",
            "Moves forward 5 metres",
            "Push and glide on the back from the wall",
            "Names two pool rules"
          ]),
          rank({"Stage %{n}", 2}, nil, 0, [], [
            "Jumps in from the side",
            "Floats on front and back",
            "Swims 5 metres front and back"
          ]),
          rank({"Stage %{n}", 3}, nil, 0, [], [
            "Swims 10 metres without aids",
            "Rotates from front to back",
            "Submerges and picks up an object"
          ]),
          rank({"Stage %{n}", 4}, nil, 0, [], [
            "10 metres of three strokes",
            "Treads water 30 seconds",
            "Sculls head first on the back"
          ]),
          rank({"Stage %{n}", 5}, nil, 0, [], [
            "25 metres of one stroke",
            "Mushroom float and handstand in water",
            "Push and glide underwater"
          ]),
          rank({"Stage %{n}", 6}, nil, 0, [], [
            "Sitting dive",
            "25 metres of three strokes",
            "Survival sequence (fall in tread signal)"
          ]),
          rank({"Stage %{n}", 7}, nil, 0, [], [
            "25 metres front crawl backstroke and breaststroke to standard",
            "50 metres without stopping",
            "Obstacle course of stage 1 to 7 skills"
          ])
        ]
      ),
      template(
        "yoga_ashtanga",
        "Ashtanga yoga series",
        "yoga",
        "level",
        :federation,
        "Mysore-style series order (teacher gives the next posture)",
        [
          rank("Sun salutations", nil, 0, [], [
            "Surya Namaskara A and B with breath",
            "Ujjayi breathing and drishti"
          ]),
          rank("Standing sequence", nil, 0, [], [
            "Standing postures to Parsvottanasana",
            "Closing sequence"
          ]),
          rank("Primary series half", nil, 0, [], [
            "Seated postures to Navasana",
            "Vinyasa between sides"
          ]),
          rank("Primary series", nil, 0, [], [
            "Full Yoga Chikitsa to Setu Bandhasana",
            "Marichyasana D bound",
            "Supta Kurmasana"
          ]),
          rank("Intermediate series", nil, 0, [], [
            "Backbends to Kapotasana",
            "Leg-behind-head postures",
            "Seven headstands"
          ]),
          rank("Advanced A", nil, 0, [], [
            "Arm balances of Advanced A",
            "Daily practice of six days a week"
          ])
        ]
      ),
      template(
        "strongman_levels",
        "Strongman Levels",
        "strongman",
        "level",
        :palee,
        "No federation runs an athlete level ladder for strongman (contests use bodyweight/novice/open classes)",
        [
          rank("Foundations", nil, 0, [], [
            "Barbell deadlift with neutral spine and full lockout",
            "Back squat to depth with braced trunk",
            "Strict overhead press with full lockout",
            "Correct belt bracing (breath into belt) on heavy sets",
            "Farmer's carry with handles: upright posture for 20 m",
            "Sandbag lap and shoulder from the floor",
            "Sled drag forward and backward",
            "Safe dropping and bailing of implements",
            "Chalk and tacky use and grip hygiene",
            "Warm-up routine for hips · shoulders · grip"
          ]),
          rank("Implement Novice", nil, 0, [], [
            "Log clean to rack in one continuous movement",
            "Log push press and log jerk with locked finish",
            "Axle continental clean to rack",
            "Axle strict and push press",
            "Atlas stone lap · stand-up and load to low platform",
            "Yoke pick: braced set-up and short steps",
            "Farmer's walk with pick · walk · controlled set-down",
            "Tyre flip with chest drive and no bicep curl",
            "Keg or sandbag carry over 20 m",
            "Frame or front carry with stable trunk",
            "Deadlift from 18-inch or with straps correctly set"
          ]),
          rank("Novice Competitor", nil, 0, [], [
            "Log press for max reps in a timed window (contest format)",
            "Ref load u95 kg: log 70 kg reps from floor in 75 s",
            "Ref load u95 kg: farmers 100 kg x 25 m under 60 s",
            "Ref load u95 kg: yoke 200 kg x 25 m under 60 s",
            "Stone series: load 3 stones of rising weight",
            "Medley: carry plus drag transition without rest",
            "Turn on yoke or farmers course where allowed",
            "Deadlift for max reps in 60 s with full lockout each rep",
            "Knows judging standards: lockout · down signal · line",
            "Weigh-in · warm-up timing and attempt planning on contest day"
          ]),
          rank("Intermediate", nil, 0, [], [
            "Circus dumbbell clean and press each arm",
            "Viking press with lockout and controlled lowering",
            "Atlas stone to shoulder-height platform",
            "Stone over bar for reps",
            "Keg toss or weight over bar with full hip drive",
            "Hussafell or sandbag bear-hug carry for distance",
            "Hercules or grip hold with braced shoulders",
            "Power stairs or loading race with fast transitions",
            "Truck or vehicle pull with harness and rope technique",
            "Runs a peaking block for a contest"
          ]),
          rank("Advanced", nil, 0, [], [
            "Log or axle press at contest-qualifying load for class",
            "Full 5-stone series on time with no misses",
            "Yoke and farmers at open-class loads with turn",
            "Car or frame deadlift with straps",
            "Medley of 3+ implements within time cap",
            "Places in a regional or national qualifier",
            "Manages weight class (cut or gain) safely",
            "Coaches a novice through stone and log technique"
          ]),
          rank("Open Competitor", nil, 0, [], [
            "Competes in open or national championship class",
            "Completes all events of a full open contest",
            "Event-specific weaknesses identified and programmed",
            "Annual competition plan with peaks and deloads",
            "Pro-level benchmark attempts logged (local→national tier)"
          ])
        ]
      ),
      template(
        "kettlebell_hardstyle",
        "Kettlebell Levels",
        "kettlebell",
        "level",
        :palee,
        "StrongFirst certifies instructors (SFG I) not students so Palee levels are built from its standards",
        [
          rank("Foundations", nil, 0, [], [
            "Hip hinge with dowel: three points of contact kept",
            "Kettlebell deadlift with neutral spine",
            "Goblet squat to depth with heels down",
            "Plank with full-body tension 30 s",
            "Hike pass to the rear with flat back",
            "Two-hand swing: hip snap and vertical plank at top",
            "Safe park of the bell after the last rep",
            "Half get-up to tall sit each side",
            "Suitcase and rack carry 20 m each side"
          ]),
          rank("Swing and Get-up", nil, 0, [], [
            "One-arm swing x10 each side with crisp lockout of hips",
            "Hand-to-hand swing switch without losing timing",
            "Full Turkish get-up x1 each side with eyes on bell",
            "Get-up high bridge and leg sweep correct",
            "Breathing matched to swing (power breath at top)",
            "10 sets of 10 two-hand swings with good form",
            "Arm bar and windmill each side"
          ]),
          rank("Clean and Press", nil, 0, [], [
            "Single clean to rack: no bell flop on forearm",
            "Rack position: wrist neutral · elbow on hip",
            "Strict press x5 each side with full lockout",
            "Front squat from rack x5 each side",
            "Clean and press ladder (1-2-3) with control",
            "Bent-over and renegade row with square hips",
            "Bottoms-up hold or press for shoulder control"
          ]),
          rank("Snatch", nil, 0, [], [
            "High pull with hip drive and relaxed grip",
            "Snatch x5 each side: punch through and no forearm bang",
            "Snatch lockout held still before descent",
            "Snatch descent without touching chest or shoulder",
            "Hand care routine (callus management)",
            "Snatch intervals with heart-rate or rest control"
          ]),
          rank("Simple Standard", nil, 0, [], [
            "100 one-arm swings in 5 min (sets of 10)",
            "10 get-ups in 10 min alternating sides",
            "Simple bell: men 32 kg swing and get-up",
            "Simple bell: women 24 kg swing · 16 kg get-up",
            "Daily practice logged for 4+ weeks"
          ]),
          rank("SFG Standard", nil, 0, [], [
            "Double-bell swing x10 to SFG standard",
            "Double clean x5",
            "Press x5 each side with SFG test bell",
            "Double front squat x5",
            "Snatch x5 each side and get-up x1 each side",
            "Snatch test 100 reps in 5 min with category bell",
            "Snatch test bell: women 12 or 16 kg · men 20/24/28 kg",
            "No 'no count' reps: elbow and knees locked at top"
          ]),
          rank("Sinister", nil, 0, [], [
            "Simple & Sinister session with Sinister bells",
            "Sinister bell: men 48 kg swing and get-up",
            "Sinister bell: women 32 kg swing · 24 kg get-up",
            "Double-bell complex (clean · press · squat) planned and executed",
            "Teaches the hinge and swing to a beginner"
          ])
        ]
      ),
      template(
        "kettlebell_sport_ranks",
        "Kettlebell Sport Ranks",
        "kettlebell",
        "level",
        :federation,
        "Russian-origin rank ladder used by IUKL/IKO and national federations: Rank 3 · Rank 2 · Rank 1 · CMS · MS · MSIC (IKMF also awards HMS · MSWC · MS · C",
        [
          rank("Rank 3", nil, 0, [], [
            "Competition bell rack: bell on chest · elbows on hips",
            "Breathing pattern in rack and overhead",
            "Jerk: half dip · bump · undersquat · fixation",
            "Snatch: soft grip · one hand switch · fixation",
            "Long cycle: clean · jerk · drop to rack · re-clean",
            "Completes 10-min set without setting bell down",
            "Reaches Rank 3 reps for own bodyweight class and bell",
            "Knows no-rep rules (fixation · touching body · drop)"
          ]),
          rank("Rank 2", nil, 0, [], [
            "Steady pace plan (reps per minute) held all 10 min",
            "Grip and hand-care routine for snatch volume",
            "Jerk lockout without press-out",
            "Biathlon: jerk set then snatch set same day",
            "Reaches Rank 2 reps for own class",
            "Uses chalk only · no gloves or wraps"
          ]),
          rank("Rank 1", nil, 0, [], [
            "Competes at amateur bell (men 24 kg · women 16 kg)",
            "Two-bell jerk or long cycle with stable rack rest",
            "Reaches Rank 1 reps for own class",
            "Periodised block towards a sanctioned meet",
            "Has completed a sanctioned competition with judges"
          ]),
          rank("CMS (Candidate Master of Sport)", nil, 0, [], [
            "Reaches CMS reps in a sanctioned meet for own class",
            "Clean pacing graph: last minute close to first",
            "Efficient hand switch under 2 s in snatch",
            "Travel and weigh-in routine for meets"
          ]),
          rank("MS (Master of Sport)", nil, 0, [], [
            "Trains with professional bell (men 32 kg · women 24 kg)",
            "Reaches MS reps at a sanctioned national or international meet",
            "Mentors lower-rank lifters in technique"
          ]),
          rank("MSIC (Master of Sport International Class)", nil, 0, [], [
            "Reaches MSIC reps at an international championship",
            "Competes with professional bell in classic events"
          ])
        ]
      ),
      template(
        "running_levels",
        "Running Levels",
        "running",
        "level",
        :palee,
        "No federation level ladder for recreational runners (England Athletics levels are for leaders/coaches)",
        [
          rank("Walk-Run Starter", nil, 0, [], [
            "5-min brisk walk warm-up and 5-min cool-down every session",
            "Run 1 min / walk 90 s x8 (C25K week 1)",
            "Three sessions a week for 3 consecutive weeks",
            "Conversational (talk test) easy pace",
            "Upright posture · relaxed shoulders · soft landing",
            "Correct running shoes and basic kit chosen",
            "Knows RPE 1-10 and keeps runs easy"
          ]),
          rank("First 5K", nil, 0, [], [
            "Run 20 min continuous (C25K week 5 run 3)",
            "Run 30 min continuous x3 in one week (C25K week 9)",
            "Completes a 5 km run or parkrun without walking",
            "Dynamic warm-up: leg swings · skips · strides",
            "Basic post-run stretching for calves · hamstrings · hips",
            "Logs runs (time · distance · RPE)"
          ]),
          rank("5K Improver", nil, 0, [], [
            "Four runs a week including one long easy run",
            "Strides x6 after easy runs",
            "Interval session (e.g. 400 m repeats) at controlled effort",
            "Running drills: A-skip · B-skip · high knees · butt kicks",
            "Runs a timed 5K and records a PB",
            "Two strength sessions a week for runners (calf · glute · core)",
            "Even pacing: second half not slower than first"
          ]),
          rank("10K", nil, 0, [], [
            "Long run of 60 min continuous",
            "Tempo run at comfortably hard effort for 20 min",
            "Hill repeats with good form uphill and downhill",
            "Completes a 10 km race or timed run",
            "Understands easy · tempo · interval training zones",
            "Recovery habits: sleep · fuel · easy days easy"
          ]),
          rank("Half Marathon", nil, 0, [], [
            "Follows a 12-week novice half plan (e.g. Higdon Novice 1)",
            "Long run progressively built to 10 miles (16 km)",
            "Practises race-day fuelling and hydration on long runs",
            "Completes 21.1 km race",
            "Taper week before race",
            "Pacing strategy written and executed"
          ]),
          rank("Marathon", nil, 0, [], [
            "Follows an 18-week novice marathon plan",
            "Long runs built from 6 to 20 miles (32 km)",
            "Four run days plus one cross-training day weekly",
            "Gels or carbs taken on schedule during 2h+ runs",
            "Three-week taper completed",
            "Completes 42.195 km marathon"
          ]),
          rank("Performance Runner", nil, 0, [], [
            "Periodised season with base · build · peak · recovery",
            "Threshold and VO2max sessions programmed weekly",
            "Uses heart-rate or pace zones from a field test",
            "Negative split in a goal race",
            "Injury-prevention routine maintained all season"
          ])
        ]
      ),
      template(
        "road_cycling_levels",
        "Road Cycling Levels",
        "cycling",
        "level",
        :palee,
        "First three Palee levels mirror the UK National Standard for Cycle Training / Bikeability: Level 1 = Roles 1-2 in traffic-free space (bike check · con",
        [
          rank("Bike Handling", nil, 0, [], [
            "Pre-ride bike check: brakes · tyres · chain · quick releases",
            "Helmet and clothing fitted correctly",
            "Start and stop under control from either pedal",
            "Ride in a straight line one-handed while signalling",
            "Look behind over shoulder without wobbling",
            "Controlled braking: both brakes · weight back",
            "Gear selection before hills and stops",
            "Avoid a hazard with a swerve or emergency stop"
          ]),
          rank("Road Ready", nil, 0, [], [
            "Start and finish an on-road journey safely",
            "Primary and secondary riding position chosen correctly",
            "Pass parked vehicles and side roads",
            "Turn left and right at simple junctions",
            "Communicate intentions with signals and eye contact",
            "Fix a puncture and refit wheel"
          ]),
          rank("Confident Road Rider", nil, 0, [], [
            "Ride complex junctions and roundabouts",
            "Multi-lane roads and lane changes with planning",
            "Plans and rides a route independently",
            "Descends with braking before corners and correct line",
            "Climbs seated and standing with cadence control",
            "Eats and drinks while riding"
          ]),
          rank("Group Rider", nil, 0, [], [
            "Holds a wheel at steady distance in a group",
            "Rides two abreast and single-file on call",
            "Uses group hand signals and calls (car back · hole · stopping)",
            "Through-and-off chain gang rotation",
            "Smooth pace when on the front · no surges",
            "Club ride of 2 h without being dropped"
          ]),
          rank("Endurance Rider", nil, 0, [], [
            "Completes a 100 km ride or sportive",
            "Fuelling plan per hour on long rides",
            "Basic bike maintenance: chain clean · lube · brake pads",
            "Bike fit checked: saddle height · reach · cleats",
            "Rides in wind and rain with suitable kit"
          ]),
          rank("Performance Cyclist", nil, 0, [], [
            "FTP field test (20-min) done and zones set",
            "Structured intervals: sweet spot · threshold · VO2max",
            "Cornering at speed with counter-steer and lean",
            "Sprint out of the saddle and in the drops",
            "Races or rides a timed event (TT · crit · gran fondo)"
          ])
        ]
      ),
      template(
        "indoor_cycling_levels",
        "Indoor Cycling Levels",
        "indoor_cycling",
        "level",
        :palee,
        "Instructor programmes (Spinning · Schwinn · Stages) certify coaches not riders",
        [
          rank("Bike Set-up", nil, 0, [], [
            "Sets saddle height: slight knee bend at bottom of stroke",
            "Sets saddle fore-aft and handlebar height",
            "Clips in or straps feet securely",
            "Uses resistance knob and emergency brake",
            "Hand positions 1 · 2 · 3 known",
            "Never spins with no resistance (always some load)",
            "Hydration and towel ready · knows when to sit and recover"
          ]),
          rank("Core Movements", nil, 0, [], [
            "Seated flat with smooth round pedal stroke",
            "Seated climb at lower cadence with added resistance",
            "Standing climb with hips over pedals",
            "Standing flat (run) with stable upper body",
            "Jumps: smooth transitions seated to standing",
            "Keeps cadence inside 60-110 rpm envelope",
            "Completes a full 45-min class"
          ]),
          rank("Intensity Control", nil, 0, [], [
            "Matches instructor RPE cues 1-10",
            "Uses heart-rate zones from a monitor",
            "Rides to the beat for cadence drills",
            "Recovers HR between intervals before next effort",
            "Sprint 20-30 s with resistance and safe deceleration"
          ]),
          rank("Power Rider", nil, 0, [], [
            "Completes a 20-min FTP test on a power bike",
            "Rides power zones on cue (watts or percent of FTP)",
            "Threshold block of 2x10 min held steady",
            "Back-to-back classes or 60+ min ride"
          ]),
          rank("Class Leader", nil, 0, [], [
            "Demonstrates every movement with correct form",
            "Builds a class profile (warm-up · main set · cool-down)",
            "Sets up a new rider's bike correctly",
            "Improves FTP between two tests"
          ])
        ]
      ),
      template(
        "rowing_levels",
        "Rowing Levels",
        "rowing",
        "level",
        :palee,
        "British Rowing Go Row Indoor technique areas (posture · grip · recovery · catch · drive · finish) and Concept2 drills (arms-and-body · pauses · counti",
        [
          rank("Stroke Basics", nil, 0, [], [
            "Foot straps set across widest part of foot",
            "Loose hook grip with flat wrists",
            "Tall posture: pivot from hips not lower back",
            "Drive order legs · body · arms",
            "Recovery order arms · body · legs",
            "Catch: shins vertical · arms long · body forward",
            "Finish: handle to lower ribs · slight lean back",
            "Reads monitor: split /500 m · stroke rate · time",
            "Sets damper and knows drag factor"
          ]),
          rank("Drills and Rhythm", nil, 0, [], [
            "Pick drill: arms only → arms and body → full slide",
            "Legs-only rowing with fixed upper body",
            "Pause drills at finish and at body-over",
            "Count rhythm: drive on 1 · recovery on 2-3-4",
            "Holds constant split at a set stroke rate",
            "Changes rate on command without losing length",
            "Rows 20 min continuous steady state"
          ]),
          rank("Fitness Rower", nil, 0, [], [
            "30-min steady row at low rate",
            "Interval sessions (e.g. 500 m repeats) with even splits",
            "Completes 5000 m test",
            "Uses heart-rate or RPE training zones",
            "Logs results in a training log or Concept2 logbook"
          ]),
          rank("Test Ready", nil, 0, [], [
            "Completes 2000 m test with a race plan (start · settle · sprint)",
            "Pacing within a narrow split range through middle 1000 m",
            "Power strokes from frontstops for a fast start",
            "Re-tests and improves 2k after a training block",
            "Posts a result to Concept2 online ranking"
          ]),
          rank("Water Transition", nil, 0, [], [
            "Capsize/swim test and water safety briefing passed",
            "Carries and launches a boat with a crew",
            "Squaring and feathering the blade",
            "Blade placement at catch and clean extraction",
            "Stops the boat and backs down on command"
          ]),
          rank("Advanced Rower", nil, 0, [], [
            "Periodised plan with UT2 · UT1 · AT · race-pace work",
            "Competes in an indoor rowing race or regatta",
            "Coaches stroke sequence to a beginner",
            "Long distance: 10 000 m or half-marathon row"
          ])
        ]
      ),
      template(
        "pilates_mat_levels",
        "Pilates Mat Levels",
        "pilates",
        "level",
        :palee,
        "No governing body sets student levels; Palee uses the widely taught classical Basic · Intermediate · Advanced mat orders (Pilatesology order sheets wi",
        [
          rank("Fundamentals", nil, 0, [], [
            "Lateral (ribcage) breathing coordinated with movement",
            "Finds neutral pelvis and imprint on demand",
            "Powerhouse engagement without breath holding",
            "Pelvic curl articulating bone by bone",
            "Chest lift with neck long",
            "Pilates stance and scapular stability",
            "Dead bug or toe taps with stable pelvis"
          ]),
          rank("Basic Order", nil, 0, [], [
            "The Hundred: 100 pumps with breath",
            "Roll Up 3-5x without momentum",
            "Single Leg Circles 3-5x each direction",
            "Rolling Like a Ball 5-10x",
            "Single Leg Stretch 5-10 sets",
            "Double Leg Stretch 5-10x",
            "Spine Stretch Forward 3-5x",
            "Flows the 7 exercises in order with transitions"
          ]),
          rank("Intermediate Order", nil, 0, [], [
            "Single and Double Straight Leg Stretch 5-10x",
            "Criss Cross 5-10 sets",
            "Open Leg Rocker 6x with balance",
            "Corkscrew 3-5 sets",
            "Saw 3-4 sets",
            "Neck Roll 3 sets",
            "Single Leg Kicks 5 sets",
            "Double Leg Kicks 3 sets",
            "Neck Pull 5x",
            "Side Kick Series: front/back · up/down · small circles",
            "Teaser 1 3x",
            "Seal 6x",
            "Full intermediate order with no rest between exercises"
          ]),
          rank("Advanced Order", nil, 0, [], [
            "Roll Over 3 sets",
            "Corkscrew with hips over 3-5 sets",
            "Swan Dive 3-5x",
            "High Scissors and High Bicycle 3-5 sets",
            "Shoulder Bridge 3-5 kicks each leg",
            "Spine Twist 3 sets",
            "Jackknife 3x",
            "Side Kicks advanced: bicycle · inner thigh · big scissors",
            "Teaser 1 · 2 · 3 3x",
            "Hip Circles 3 sets",
            "Swimming 3 breaths",
            "Leg Pull Front and Leg Pull Back 3 sets"
          ]),
          rank("Master Repertoire", nil, 0, [], [
            "High Bridge 1x",
            "Kneeling Side Kicks 4 sets",
            "Mermaid 3 sets and Side Bend 3x each side",
            "Snake/Twist 3 sets",
            "Boomerang 3 sets",
            "Crab 3-6x and Rocking 5x",
            "Control Balance 3x",
            "Push Ups 3-10x",
            "Full Return to Life 34-exercise order in sequence",
            "Flowing transitions with no breaks in the full order"
          ])
        ]
      ),
      template(
        "pilates_reformer_levels",
        "Pilates Reformer Levels",
        "pilates",
        "level",
        :palee,
        "Exercise names and their sequence come from the classical Universal Reformer order (Online Pilates Classes · 46 items from Footwork to Russian Squat)",
        [
          rank("Reformer Orientation", nil, 0, [], [
            "Safe getting on and off the carriage",
            "Changes springs · headrest and footbar safely",
            "Neutral spine and breathing on the carriage",
            "Footwork: toes · arches · heels · tendon stretch",
            "Controls carriage return without banging"
          ]),
          rank("Basic Reformer", nil, 0, [], [
            "The Hundred on the reformer",
            "Frogs and leg circles in straps",
            "Stomach Massage round back",
            "Short Box: round back and flat back",
            "Elephant with carriage control",
            "Knee Stretches round and flat",
            "Running and Pelvic Lift",
            "Rowing into the sternum and 90 degrees",
            "Basic order flowed with correct spring changes"
          ]),
          rank("Intermediate Reformer", nil, 0, [], [
            "Coordination",
            "Full Rowing series (1-6)",
            "Long Box: Pull Straps · T Pull · Backstroke",
            "Long Box: Teaser and Breaststroke",
            "Long Stretch series: Long · Down · Up Stretch",
            "Long Back Stretch",
            "Short Box: side to side · twist and reach · tree",
            "Short Spine Massage",
            "Semi Circle",
            "Chest Expansion and Thigh Stretch",
            "Knee Stretches knees off",
            "Side Splits",
            "Mermaid"
          ]),
          rank("Advanced Reformer", nil, 0, [], [
            "Overhead",
            "Swan on the footbar",
            "Horseback and Hamstring Curls",
            "Single Leg Elephant",
            "Tendon Stretch and Single Leg Tendon Stretch",
            "Side Sit Ups",
            "Backbends and Arm Circles",
            "Snake and Twist",
            "Corkscrew and Tic Toc",
            "Second Long Box: Grasshopper · Swimming · Rocking",
            "Long Spine Massage",
            "High Bridge",
            "Front Splits"
          ]),
          rank("Master Reformer", nil, 0, [], [
            "Headstands facing down and facing up",
            "Headstands with straps",
            "Control Balance Off",
            "Control Balance Push Ups front and back",
            "Star",
            "Russian Splits",
            "Russian Squat",
            "Full classical reformer order in sequence"
          ])
        ]
      ),
      template(
        "mobility_levels",
        "Mobility Levels",
        "mobility",
        "level",
        :palee,
        "No standard level system",
        [
          rank("Joint Health", nil, 0, [], [
            "Daily CARs routine: neck · shoulders · spine · hips · ankles",
            "Deep squat hold 60 s with heels down (assisted ok)",
            "Hip hinge toe-reach with straight knees",
            "90/90 hip switch without hands",
            "Wall shoulder flexion: arms overhead with ribs down",
            "Glute bridge hold 30 s",
            "Cat-cow segmental spine control"
          ]),
          rank("Range Builder", nil, 0, [], [
            "Couch stretch 60 s each side upright",
            "Half split with front heel on block 30 s",
            "Seated pike: hands reach past toes",
            "Straddle sit upright with hands on floor in front",
            "Table-top bridge with hips level",
            "Thoracic rotation open book 10 each side",
            "Ankle knee-to-wall test progression logged"
          ]),
          rank("Active Flexibility", nil, 0, [], [
            "PAILs and RAILs in hip 90/90 paired",
            "Active straight-leg raise held 5 s each side",
            "Jefferson curl light with segmental control",
            "Cossack squat to full depth each side",
            "Head-on-floor bridge (crown) with control",
            "Shoulder dislocates with band or dowel",
            "Front split with hips on cushion or blocks"
          ]),
          rank("Intermediate Shapes", nil, 0, [], [
            "Full bridge from floor with arms straight",
            "Pike fold chest toward thighs with flat back",
            "Pancake: elbows to floor in straddle",
            "Front split within a hand-width of floor each side",
            "Middle split hips at knee height or lower",
            "Skin-the-cat or German hang shoulder extension",
            "Pigeon pose upright with square hips"
          ]),
          rank("Advanced Shapes", nil, 0, [], [
            "Full front split on floor both sides with square hips",
            "Chest-to-floor pancake",
            "Bridge with shoulders over wrists and straight legs",
            "Wall walk-down to bridge and back up",
            "Active pike compression: lift legs from floor in pike",
            "Deep squat with arms overhead and upright torso"
          ]),
          rank("Elite Mobility", nil, 0, [], [
            "Middle split on floor",
            "Standing drop-back to bridge without wall",
            "Stand up from bridge to standing",
            "Oversplit or split with back-leg bend (needle prep)",
            "Maintains end-range strength routine 3x weekly"
          ])
        ]
      ),
      template("hiit_levels", "HIIT Levels", "hiit", "level", :palee, "No level system exists", [
        rank("Starter", nil, 0, [], [
          "Completes 30 s work / 15 s rest intervals at RPE 4-6",
          "Bodyweight squat to depth with heels down",
          "Incline or knee push-up with straight body line",
          "Step-back burpee without jump",
          "Forearm plank 30 s",
          "Reverse lunge with knee control",
          "Knows RPE scale and when to scale down",
          "Completes a full 30-min class with modifications"
        ]),
        rank("Foundations", nil, 0, [], [
          "Equal work:rest intervals (e.g. 40:40) sustained",
          "Full push-up x10 with chest to fist height",
          "Full burpee with chest to floor x10",
          "Jump squat with soft landing",
          "Mountain climbers with hips level 30 s",
          "Kettlebell or dumbbell swing with hip hinge",
          "Bear crawl forward and back 10 m",
          "Jumping jacks and high knees for 60 s"
        ]),
        rank("Intermediate", nil, 0, [], [
          "Tabata 20:10 x8 with consistent reps",
          "EMOM 10 min with planned reps",
          "Jumping lunges with upright torso",
          "Box or step jump with full hip extension and step down",
          "Plank variations: shoulder taps and side plank 30 s",
          "Shuttle sprints with sharp turns",
          "Medicine-ball slams and throws",
          "Partner drills (wheelbarrow · plank high-fives)"
        ]),
        rank("Advanced", nil, 0, [], [
          "Work:rest of 2:1 or longer intervals at RPE 8-9",
          "Burpee broad jumps or burpee box jumps",
          "Plyometric push-up",
          "Sled push or sprint intervals outdoors",
          "AMRAP 20 min with steady pacing",
          "Heart-rate recovery tracked between rounds",
          "Bootcamp obstacle or partner carry course"
        ]),
        rank("Athlete", nil, 0, [], [
          "Completes a benchmark HIIT test and re-tests to improve",
          "Scales any session for self and a partner",
          "Leads warm-up and demonstrates all standards",
          "Balances HIIT with recovery days (max 2-3 hard/week)"
        ])
      ]),
      template(
        "strength_levels",
        "Strength Training Levels",
        "strength",
        "level",
        :palee,
        "Palee levels follow the novice → advanced novice → intermediate → advanced stages popularised by Rippetoe's Practical Programming (novice adds load ev",
        [
          rank("Movement Foundations", nil, 0, [], [
            "Squat pattern: goblet squat to depth",
            "Hinge pattern: Romanian deadlift with neutral spine",
            "Push: push-up with straight body x10",
            "Pull: inverted row or assisted pull-up",
            "Lunge or split squat with knee tracking",
            "Loaded carry with tall posture",
            "Bracing: Valsalva breath before each rep",
            "Warm-up sets ramp to working weight"
          ]),
          rank("Novice Lifter", nil, 0, [], [
            "Barbell back squat below parallel",
            "Bench press with arch · leg drive · bar touch chest",
            "Standing overhead press with full lockout",
            "Conventional deadlift from floor each rep reset",
            "Power clean or barbell row technique",
            "Linear progression: adds load each session for 8+ weeks",
            "Sets safety pins or uses a spotter correctly",
            "Logs every session (sets · reps · load)"
          ]),
          rank("Advanced Novice", nil, 0, [], [
            "Heavy and light squat days within the week",
            "Chin-up or pull-up strict x5",
            "Deadlift 1.5x bodyweight (Dan John 'expected' ref)",
            "Manages a stall with a reset or deload",
            "Uses RPE or reps in reserve on top sets",
            "Belt and lifting shoes used appropriately"
          ]),
          rank("Intermediate Lifter", nil, 0, [], [
            "Weekly progression programme (e.g. Texas Method or 5/3/1)",
            "Volume · intensity and recovery days structured in the week",
            "Accessory work chosen for weak points",
            "Tests a 1RM or rep max safely with spotters",
            "Front squat and pause variations",
            "Bodyweight bench press for reps"
          ]),
          rank("Advanced Lifter", nil, 0, [], [
            "Block or monthly periodisation planned",
            "Deadlift 2x bodyweight (Dan John 'game changer' ref)",
            "Pull-ups x15 strict (Dan John 'game changer' ref)",
            "Bodyweight squat x15 (Dan John 'game changer' ref)",
            "Autoregulates load from daily readiness",
            "Coaches a novice through the main lifts"
          ])
        ]
      )
    ]
  end
end
