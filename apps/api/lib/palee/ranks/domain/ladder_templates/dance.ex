defmodule Palee.Ranks.Domain.LadderTemplates.Dance do
  @moduledoc "Template ladders: Dance, pole and aerial (ADR-400; sources in docs/research/rank-curricula-research-2026-11-03.md)."

  import Palee.Ranks.Domain.LadderTemplates.Build

  def all do
    [
      template(
        "ballet_rad_graded",
        "Ballet graded levels (RAD structure)",
        "ballet",
        "level",
        :federation,
        "RAD graded structure (not affiliated)",
        [
          rank({:exam, "Pre-Primary"}, nil, 0, [], [
            "Posture and parallel feet",
            "Pointing and flexing feet",
            "Skips and galops to music",
            "Free movement to a story"
          ]),
          rank({:exam, "Primary"}, nil, 0, [], [
            "First position and demi-plie",
            "Transfer of weight and balance on demi-pointe",
            "Sautes in first position",
            "Curtsey or bow and a dance"
          ]),
          rank({"Grade %{n}", 1}, nil, 0, [], [
            "Plies in first and second",
            "Battements tendus",
            "Port de bras first to fifth",
            "Character dance"
          ]),
          rank({"Grade %{n}", 2}, nil, 0, [], [
            "Glissés and retirés",
            "Changements and echappes sautes",
            "Polka and spring points"
          ]),
          rank({"Grade %{n}", 3}, nil, 0, [], [
            "Pirouette preparations and quarter turns",
            "Petit allegro with assembles",
            "Grand battement"
          ]),
          rank({"Grade %{n}", 4}, nil, 0, [], [
            "Single pirouette en dehors",
            "Glissade and jeté combinations",
            "Adage with developpes"
          ]),
          rank({"Grade %{n}", 5}, nil, 0, [], [
            "Pirouettes en dedans",
            "Grand jeté and sissonne",
            "Free movement section"
          ]),
          rank({"Grade %{n}", 6}, nil, 0, [], [
            "Fouette preparations and double pirouette drills",
            "Batterie (entrechat quatre)",
            "Character and free movement dances"
          ]),
          rank({"Grade %{n}", 7}, nil, 0, [], [
            "Grand allegro sequences",
            "Advanced adage with balances"
          ]),
          rank({"Grade %{n}", 8}, nil, 0, [], [
            "Solo performance with artistry",
            "Music and style interpretation across eras"
          ])
        ]
      ),
      template(
        "ballet_rad_vocational",
        "Ballet vocational levels (RAD structure)",
        "ballet",
        "level",
        :federation,
        "RAD vocational structure (not affiliated)",
        [
          rank({:exam, "Intermediate Foundation"}, nil, 0, [], [
            "Barre and centre at vocational standard",
            "Pointe work introduction",
            "Double pirouette en dehors"
          ]),
          rank({:exam, "Intermediate"}, nil, 0, [], [
            "Pointe enchaînements",
            "Fouetté rond de jambe en tournant",
            "Grand allegro with tours en l'air (male)"
          ]),
          rank({:exam, "Advanced Foundation"}, nil, 0, [], [
            "Multiple pirouettes and fouettés",
            "Batterie with entrechat six"
          ]),
          rank({:exam, "Advanced 1"}, nil, 0, [], [
            "Classical solo variation",
            "Sustained adage on pointe"
          ]),
          rank({:exam, "Advanced 2"}, nil, 0, [], [
            "Professional-level class",
            "Two solo variations"
          ]),
          rank({:exam, "Solo Seal"}, nil, 0, [], ["Solo Seal variations and own solo"])
        ]
      ),
      template(
        "contemporary_grades",
        "Contemporary dance grades",
        "contemporary_dance",
        "level",
        :palee,
        "Palee grades (the ISTD has no graded contemporary exams)",
        [
          rank({"Grade %{n}", 1}, nil, 0, [], [
            "Parallel and turned-out positions",
            "Spinal curves and contractions",
            "Floor rolls and weight transfer"
          ]),
          rank({"Grade %{n}", 2}, nil, 0, [], [
            "Swings and suspensions",
            "Falls and recovery",
            "Travelling phrase with direction changes"
          ]),
          rank({"Grade %{n}", 3}, nil, 0, [], [
            "Spirals and tilts",
            "Inversions with safe weight bearing",
            "Improvised task"
          ]),
          rank({"Grade %{n}", 4}, nil, 0, [], [
            "Release technique phrases",
            "Jumps with spine articulation",
            "Partner contact basics"
          ]),
          rank({"Grade %{n}", 5}, nil, 0, [], [
            "Floor work sequences",
            "Contact improvisation lifts",
            "Own short choreography"
          ]),
          rank({"Grade %{n}", 6}, nil, 0, [], [
            "Performance of a set solo",
            "Choreography with a clear intention"
          ])
        ]
      ),
      template(
        "latin_medals",
        "Latin American medal levels",
        "latin_dance",
        "level",
        :federation,
        "Medal tests like the ISTD and IDTA (not affiliated)",
        [
          rank("Social", nil, 0, [], [
            "Cha cha and rumba basic movement",
            "Leading and following in closed hold"
          ]),
          rank("Bronze", nil, 0, [], [
            "Chosen dances from cha cha samba rumba paso doble and jive",
            "Bronze figures with timing",
            "Hip action (Cuban motion)"
          ]),
          rank("Silver", nil, 0, [], [
            "Silver figures in the chosen dances",
            "Spins and turns with spotting"
          ]),
          rank("Gold", nil, 0, [], [
            "Gold figures in the chosen dances",
            "Musicality and floorcraft"
          ]),
          rank("Gold Star", nil, 0, [], [
            "Gold Star awards in the chosen dances",
            "Competition-ready routines"
          ])
        ]
      ),
      template(
        "salsa_levels",
        "Salsa levels",
        "latin_dance",
        "level",
        :palee,
        "Palee levels (common school progression)",
        [
          rank({"Beginner %{n}", 1}, nil, 0, [], [
            "Basic step on1 or on2 in time",
            "Side basic and back basic",
            "Right turn for the follower",
            "Cross-body lead"
          ]),
          rank({"Beginner %{n}", 2}, nil, 0, [], [
            "Left turn and inside turn",
            "Open and closed hold changes",
            "Hears the clave and the one"
          ]),
          rank("Improver", nil, 0, [], [
            "Cross-body lead variations",
            "Copa and hammerlock",
            "Basic shines"
          ]),
          rank("Intermediate", nil, 0, [], [
            "Double turns with spotting",
            "Hand-change combinations",
            "Styling for leaders and followers"
          ]),
          rank("Advanced", nil, 0, [], [
            "Multiple spins and turn patterns",
            "Shines in partnerwork",
            "Musical breaks and accents"
          ]),
          rank("Performance", nil, 0, [], [
            "Team choreography",
            "Lifts and dips with safe technique"
          ])
        ]
      ),
      template(
        "bachata_levels",
        "Bachata levels",
        "latin_dance",
        "level",
        :palee,
        "Palee levels (sensual and Dominican styles)",
        [
          rank({"Beginner %{n}", 1}, nil, 0, [], [
            "Basic step with the tap on 4 and 8",
            "Side and box basics",
            "Closed and open hold"
          ]),
          rank({"Beginner %{n}", 2}, nil, 0, [], [
            "Right and left turns",
            "Hip motion in time",
            "Leading through the frame"
          ]),
          rank("Improver", nil, 0, [], [
            "Body rolls and waves (sensual)",
            "Dominican footwork",
            "Turn combinations"
          ]),
          rank("Intermediate", nil, 0, [], [
            "Head rolls and hair whips with neck safety",
            "Musicality: breaks and the derecho",
            "Connection in close embrace"
          ]),
          rank("Advanced", nil, 0, [], [
            "Counter-body movements and isolations",
            "Dips and drops with safe technique",
            "Social leading of complex patterns"
          ])
        ]
      ),
      template(
        "hiphop_levels",
        "Hip-hop levels",
        "street_dance",
        "level",
        :federation,
        "ISTD street dance medals plus a Palee starter level",
        [
          rank("Starter", nil, 0, [], [
            "Bounce and rock grooves",
            "Two-step and side step",
            "On-beat counting in eights"
          ]),
          rank("Bronze", nil, 0, [], [
            "Running man and Roger Rabbit",
            "Party dances: Bart Simpson and Cabbage Patch",
            "32-count routine"
          ]),
          rank("Silver", nil, 0, [], [
            "Isolations: chest head and arms",
            "Footwork: kick ball change and heel-toe",
            "Freestyle 30 seconds in a circle"
          ]),
          rank("Gold", nil, 0, [], [
            "Texture changes (hit glide and flow)",
            "Choreography with formations",
            "Freestyle battle round"
          ])
        ]
      ),
      template(
        "commercial_rnb_levels",
        "Commercial and R&B levels",
        "street_dance",
        "level",
        :palee,
        "Palee levels for commercial dance classes",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Grooves in R&B tempo",
            "Body rolls and isolations",
            "Learns an 8-count phrase quickly"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Floor transitions and knee spins",
            "Facials and performance to camera",
            "64-count choreography"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Speed changes and accents on lyrics",
            "Turns and jumps within choreography"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Music video style piece",
            "Own choreography for a short track"
          ])
        ]
      ),
      template(
        "breaking_levels",
        "Breaking levels",
        "street_dance",
        "level",
        :palee,
        "Palee levels from WDSF breaking elements",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Toprock: Indian step and two-step",
            "Six-step",
            "Baby freeze"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Three-step and CC footwork",
            "Chair freeze",
            "Go-down transitions"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Backspin and turtle drills",
            "Headstand freeze",
            "Combo of toprock footwork and freeze"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Windmill",
            "Air baby and hollowback drills",
            "One-minute set in a cypher"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Flares or headspins",
            "Power move combos",
            "Battle rounds with musicality"
          ])
        ]
      ),
      template(
        "reggaeton_levels",
        "Reggaeton levels",
        "street_dance",
        "level",
        :palee,
        "Palee levels (urban Latin)",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Dembow rhythm in the feet",
            "Basic perreo step with safe posture",
            "Hip circles"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Isolations of hips and chest",
            "Travelling steps and turns",
            "32-count routine"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Floor work and level changes",
            "Accents on the snare",
            "Freestyle 30 seconds"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Performance choreography with styling",
            "Partner reggaeton basics"
          ])
        ]
      ),
      template(
        "heels_levels",
        "Heels levels",
        "street_dance",
        "level",
        :palee,
        "Palee levels for heels classes",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Walks and turns in heels with ankle control",
            "Posture and hip sway",
            "Hair flicks with neck safety"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Floor work: kneeling transitions",
            "Leg lines and extensions",
            "32-count choreography"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Floor spins and slides",
            "Chair work basics",
            "Performance with facials"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Drops and splits in heels (when flexible enough)",
            "Own short choreography"
          ])
        ]
      ),
      template(
        "pole_levels",
        "Pole levels",
        "pole_aerial",
        "level",
        :palee,
        "Palee levels from common studio grading",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Walks and pivots around the pole",
            "Fireman spin and back hook spin",
            "Chair spin",
            "Basic climb and sit"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Pole sit hands-free",
            "Crucifix",
            "Spin combinations on static and spinning pole",
            "Inverted crunch drills"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Basic invert from the floor",
            "Outside leg hang and inside leg hang",
            "Butterfly"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Aerial invert",
            "Shoulder mount from the floor",
            "Gemini and cupid"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Ayesha (elbow grip)",
            "Deadlift shoulder mount",
            "Iron X drills"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Handspring (twisted grip)",
            "Flags and drops with control",
            "Routine of 2 minutes on both sides"
          ])
        ]
      ),
      template(
        "aerial_silks_levels",
        "Aerial silks levels",
        "pole_aerial",
        "level",
        :palee,
        "Palee levels from circus school progression",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Single foot lock from the ground",
            "Basic climb (Russian or French)",
            "Invert in the knot"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Double foot locks in the air",
            "Hip key",
            "Straddle back inversion",
            "Scorpion and diaper wrap"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Inverted climb",
            "Single star drop",
            "Sequence of three poses"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Wheel-downs",
            "Salto drop",
            "Belay and Russian climbs mixed"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], ["Double star drop", "Aerial routine of 2 minutes"])
        ]
      ),
      template(
        "aerial_hoop_levels",
        "Aerial hoop levels",
        "pole_aerial",
        "level",
        :palee,
        "Palee levels from circus school progression",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Hip-hang and seated mount from the ground",
            "Bird's nest under the bar",
            "Pike beat mount drills"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Pike beat mount",
            "Mermaid and man in the moon",
            "Spinning poses"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Front balance and back balance",
            "Gazelle",
            "Straddle mount"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], ["Angel and top-bar standing", "Ankle hang"]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Rolls and drops with control",
            "Routine of 2 minutes"
          ])
        ]
      ),
      template(
        "tap_grades",
        "Tap dance",
        "dance",
        "level",
        :federation,
        "ISTD tap structure (not affiliated)",
        [
          rank({:exam, "Pre-Primary"}, nil, 0, [], [
            "Bounce in time to music",
            "Step and jump with clear sounds",
            "Ball taps and ball beats",
            "Toe taps",
            "Heel beats",
            "Step ball change",
            "Gallops across the room",
            "Step clap stamp clap pattern",
            "Keeps a steady beat when clapping",
            "Performs a short teacher-led tap routine"
          ]),
          rank({:exam, "Primary"}, nil, 0, [], [
            "All Pre-Primary steps clean and in time",
            "Ball change",
            "Single paradiddle (paddle)",
            "Preparation for shuffles (forward and back brush)",
            "Ball and heel beats sequence",
            "Skips and travelling steps to music",
            "Claps a simple given rhythm",
            "Performs a short dance with a partner or group"
          ]),
          rank({"Grade %{n}", 1}, nil, 0, [], [
            "Tap step and heel tap",
            "Ball dig and heel dig",
            "Spring",
            "Forward shuffle",
            "Standard flap and flaps to the toe",
            "Basic crawl and sideways crawl (feet together)",
            "Pick up step",
            "Tap step ball change",
            "Shuffle ball change",
            "Rag style: step heel beat",
            "Jazz style: pick up steps",
            "Boogie style: tap step heels and tap step ball change",
            "Swing style: shuffle ball changes",
            "Blues style: ball changes",
            "Performs a solo dance up to 45 seconds"
          ]),
          rank({"Grade %{n}", 2}, nil, 0, [], [
            "Stomp and drop",
            "Side shuffle and shuffles round the side",
            "4 beat cramp roll",
            "Pick ups on 2 feet",
            "Pick up spring and pick up hop",
            "Shuffle hop step",
            "4 beat riff",
            "Separated crawl sideways",
            "Double paradiddle (paddle)",
            "Single time step",
            "Travelling pick ups (Celtic style)",
            "Turning step on the diagonal both sides"
          ]),
          rank({"Grade %{n}", 3}, nil, 0, [], [
            "Toe flam",
            "Back shuffle",
            "5 beat cramp roll",
            "3 beat riff forward and 5 beat riff",
            "Pick up on 1 foot (with preparation)",
            "Pick up change and pick up ball change",
            "Shuffle spring",
            "Basic waltz step single and double",
            "Double time step",
            "Paddles exercise",
            "Unseen sequence of 2 known steps set by teacher"
          ]),
          rank({"Grade %{n}", 4}, nil, 0, [], [
            "Double shuffle",
            "Flap to toe sideways",
            "3 beat riff forwards and backwards",
            "3 beat ripple",
            "Shuffle pick up change",
            "Pull back (on two feet)",
            "Bufalino crawl and close work crawl",
            "Riffs and cramp rolls in 3/4",
            "Triple time steps",
            "Claps 16th notes and improvises footwork",
            "Turning step both sides"
          ]),
          rank({"Grade %{n}", 5}, nil, 0, [], [
            "3 beat paddle",
            "Double shuffle to the side",
            "Flam",
            "4 beat ripple",
            "Round the sides",
            "3 beat and 4 beat wing preparation",
            "Maxi Ford with toe tap",
            "Sugars",
            "Pick up time steps single double and triple",
            "Shuffle time step solo",
            "Basic Shim Sham",
            "Optional: double wings and toe beat crawl"
          ]),
          rank({"Grade %{n}", 6}, nil, 0, [], [
            "4 beat progressive tap",
            "Criss cross shuffle",
            "Progressive shuffle",
            "4 beat cramp roll change",
            "Double scuffle and twist scuffle",
            "5 beat open riff",
            "Wing preparations in sequence",
            "Single · double · triple shuffle time steps with breaks and half breaks",
            "Time steps starting on 8 or on 1",
            "Solo dance of own style choice"
          ]),
          rank({:exam, "Intermediate"}, nil, 0, [], [
            "Slap · splat · snatch and slam",
            "3 beat shuffles · flaps and pull backs",
            "Drum cramp roll and 6 beat cramp roll",
            "Inside flam and outside flam",
            "Suzie Q",
            "Maxi Ford with step",
            "Cahito",
            "Compass turn and rhythm turn with shuffle",
            "Shuffle off to Buffalo",
            "5 beat paddle",
            "6 beat and 7 beat riffs",
            "11 beat criss cross riff",
            "Ripple down",
            "Rhythm · travelling and wing-preparation time steps",
            "Cross accent and light and shade exercises",
            "Theatre tap and commercial tap sequences",
            "Own dance composition up to 2 minutes"
          ]),
          rank({:exam, "Advanced 1"}, nil, 0, [], [
            "Progressive taps",
            "Roll time steps",
            "12 beat criss cross riffs",
            "Closed pull backs",
            "2 bar single · double and triple wing preparation time steps",
            "Turning step with Maxi Ford",
            "Suzie Q technical exercise",
            "Examiner-set time steps with syncopation and tacet",
            "Improvises a 2 bar 4/4 rhythm with 16ths",
            "Blues and quick jazz sequences",
            "Optional: mixed Maxi Ford · wing on one foot · wing change"
          ]),
          rank({:exam, "Advanced 2"}, nil, 0, [], [
            "Single · double · triple and double-triple cramp roll time steps",
            "4 beat press cramp roll",
            "Syncopated shuffle pick up change",
            "Open and closed pull backs",
            "Eddie's riff and Eddie's travel",
            "Rattle: basic · progressive and double toe",
            "Back travel and side travel",
            "Wings or ripples turning",
            "Spanish waltz amalgamation",
            "Free improvisation to examiner's music",
            "Optional: pendulum wings"
          ])
        ]
      ),
      template(
        "jazz_grades",
        "Jazz dance",
        "dance",
        "level",
        :federation,
        "ISTD Modern Theatre structure (not affiliated)",
        [
          rank({:exam, "Primary"}, nil, 0, [], [
            "Natural walks on the diagonal in time",
            "Limbering: magic feet · leg stretching · squeeze and stretch",
            "Running in a circle with control",
            "Claps and marks a simple rhythm (1234&5)",
            "Skipping and galloping patterns",
            "Bounces together with the group",
            "Running with action (arms and focus)",
            "Performs a 45-second character dance"
          ]),
          rank({"Grade %{n}", 1}, nil, 0, [], [
            "Set warm-up from memory",
            "Side stretch and forward stretch",
            "Foot exercise: point and flex",
            "Abdominal strengthening exercise",
            "Front kicks with straight legs",
            "Tendus in parallel",
            "Jazz walks in a circle",
            "Step ball change",
            "Split runs",
            "Basic turn on the spot",
            "Claps and marks a 2-bar free rhythm",
            "Solo dance of 16 bars"
          ]),
          rank({"Grade %{n}", 2}, nil, 0, [], [
            "Limbering sequence with spine roll-downs",
            "Front kicks to 90° with control",
            "Simple head and shoulder isolations",
            "Jazz walks with arm lines",
            "Step ball change travelling",
            "Jazz pas de bourrée on the spot",
            "Chassé travelling",
            "Step turn at low level",
            "Sautés in parallel",
            "Set rhythm 1&2 3&4 clapped and danced",
            "Set amalgamation from memory"
          ]),
          rank({"Grade %{n}", 3}, nil, 0, [], [
            "Side stretch option A or B",
            "Leg stretching with front kicks",
            "Side kicks exercise",
            "Head · shoulder · ribcage and hip isolations",
            "Triple runs",
            "Jazz pas de bourrée travelling",
            "Split jump",
            "Step and front kick",
            "Front and side step ball change",
            "Step turn at high and low level",
            "Front and side flick kicks",
            "Claps and marks free rhythm with half and quarter notes"
          ]),
          rank({"Grade %{n}", 4}, nil, 0, [], [
            "Forward and side stretch with spine loosening",
            "Front and side kicks set exercise",
            "Hip loosening or push-aways exercise",
            "Body strengthening floor sequence",
            "Set isolation exercise",
            "Free rhythm with 12th notes and missed beats",
            "Single turns both sides",
            "Kicks set exercise both sides",
            "Split runs travelling",
            "Two combination steps danced consecutively",
            "Solo dance of 1 to 1½ minutes"
          ]),
          rank({"Grade %{n}", 5}, nil, 0, [], [
            "Isolations seen individually",
            "Improvisation to unseen music",
            "Drag runs forwards and sideways",
            "Step and sideways split run",
            "Step and forward split run",
            "Circular spring without body line",
            "Accented hop",
            "Step and coupé turn with extended leg",
            "Turns option A or B both sides",
            "Unset sequence given by the teacher",
            "Jazz · musical theatre or lyrical amalgamation"
          ]),
          rank({"Grade %{n}", 6}, nil, 0, [], [
            "Limbering set exercise with full range",
            "Jazz arm exercise",
            "Step and retiré with body line and fondu",
            "Tilts",
            "Extended spring sideways",
            "Accented hop with varying leg line",
            "Accented hop with half turn",
            "Forward leap",
            "Kicks option A or B",
            "Dance vocabulary sequence with 4-count improvisation",
            "Lyrical · musical theatre or jazz amalgamation"
          ]),
          rank({:exam, "Intermediate Foundation"}, nil, 0, [], [
            "Circular walk and triple run",
            "Drag run",
            "Jazz change of weight",
            "Jazz pas de bourrée travelling · turning and on the spot",
            "Drag turns front and back",
            "Jazz pirouette at low level",
            "Twist turn and swivel turn",
            "Travelling jump with turn",
            "Front kick with bent or straight supporting leg",
            "Extended spring sideways and accented hops",
            "Circular spring and forward leap",
            "Isolations and set rhythm clapping"
          ]),
          rank({:exam, "Intermediate"}, nil, 0, [], [
            "Barre work: figure of 8 leg swings",
            "Développé walk with lay back",
            "Trudging · cushion and circular walks",
            "Jazz pas de bourrée turning",
            "Single pirouettes outwards and inwards at low and high level",
            "Front and back twist turns · spin · open turns",
            "Front · side and round kicks",
            "Side kick with tilt",
            "Forward leap with développé",
            "Extended tuck jump",
            "Step and spring turn with picked-up leg",
            "Split · picked-up and turning ball changes",
            "Leaps on the diagonal and elevated turns",
            "Interprets free rhythm with syncopation"
          ]),
          rank({:exam, "Advanced 1"}, nil, 0, [], [
            "Jazz adage set exercise",
            "Falls: knee drop and back fall",
            "Triple walk and walks set exercise",
            "Double pirouettes at low and high level",
            "Barrel turn (single or more)",
            "Single turn with leg in attitude",
            "Multiple pirouettes in 2nd with fouetté action",
            "Kicks with hip extension front and side",
            "Round kicks outward and inward",
            "Développé side leap and stag leap",
            "Leap turn with varying leg lines",
            "Accented hops with a whole turn",
            "Improvises immediately to examiner's free amalgamation"
          ]),
          rank({:exam, "Advanced 2"}, nil, 0, [], [
            "Technical floor sequence",
            "Falls and tilts set exercise",
            "Extended walks with body tilt",
            "Double or more pirouettes in parallel or turned out",
            "Spin turns (chaînés) at various levels",
            "Barrel turns with bent or straight legs",
            "Double tour en l'air",
            "Kicks with layout or back bend",
            "Attitude leaps and scissor hop",
            "Jazz sissonne and straddle jump",
            "Turns on the diagonal set exercise",
            "Two contrasting set amalgamations (e.g. blues)",
            "Own solo of 1½ minutes"
          ])
        ]
      ),
      template(
        "ballet_cecchetti",
        "Ballet (Cecchetti method)",
        "ballet",
        "level",
        :federation,
        "ISTD Cecchetti structure (not affiliated)",
        [
          rank({:exam, "Pre-Primary"}, nil, 0, [], [
            "Demi-pliés in 1st position",
            "Walking on tip toes",
            "Flexing and pointing the feet",
            "Point and close",
            "Curling and stretching the body",
            "Hand movements to music",
            "Jumps in 1st position",
            "Responds to music in imaginative scenes",
            "Curtsey or bow"
          ]),
          rank({:exam, "Primary"}, nil, 0, [], [
            "Skips into the room to music",
            "Demi-pliés and rises",
            "Battement tendu",
            "Foot stretching and marching",
            "Hand exercises · arm lifting · arm sways",
            "Sautés",
            "Galops sideways and pony canters forwards",
            "Échappés sautés",
            "Preparatory polka with spring points",
            "Improvises to unheard music",
            "Expressive solo up to 45 seconds"
          ]),
          rank({"Grade %{n}", 1}, nil, 0, [], [
            "Knows points of the room corners 1-4",
            "Knows 1st · 2nd and 3rd positions of the feet",
            "Barre: demi-pliés in 2nd and 1st",
            "Battements tendus à la seconde facing the barre",
            "Grands battements devant sideways to the barre",
            "Rises combined with running on the toes",
            "Port de bras in the centre",
            "Retirés and exercise for 3rd arabesque",
            "Quarter turns with use of the head",
            "Échappé sauté from 1st with sautés",
            "Simple sideways polka with spring points",
            "Posé temps levé and galops",
            "Classical or demi-caractère solo up to 45 seconds",
            "Révérence"
          ]),
          rank({"Grade %{n}", 2}, nil, 0, [], [
            "Works in 3rd position of the feet",
            "Knows 4th and 5th positions and arm positions 2nd · 5th en bas/avant/haut",
            "Rise and demi-pliés in 2nd · 1st and 3rd",
            "Battements tendus en croix",
            "Grands battements devant and à la seconde",
            "Ronds de jambe à terre",
            "Échappés relevés",
            "Retiré passé",
            "Preparatory exercise for tour en l'air (head use)",
            "Pas de chat with changements",
            "Petits jetés devant or derrière",
            "Balletic polka forwards and sideways",
            "Unseen enchaînement with échappés and changements"
          ]),
          rank({"Grade %{n}", 3}, nil, 0, [], [
            "Works in 5th position of the feet",
            "Knows directions of the body and terms plier and sauter",
            "Battements dégagés from 1st",
            "Grands battements derrière facing the barre",
            "Battements frappés",
            "Retirés and développés",
            "Fouetté à terre into arabesque",
            "Développé and temps lié in the centre",
            "1st and 3rd arabesques",
            "Relevés with bourrée en tournant",
            "Preparation for pirouette en dehors",
            "Assemblés dessus and dessous soutenu",
            "Pas de bourrée dessous soutenu and de suite",
            "Jetés temps levés with coupés",
            "Balancés sideways"
          ]),
          rank({"Grade %{n}", 4}, nil, 0, [], [
            "Knows five positions of the head and arabesques 1-3",
            "Full pliés in 2nd · 1st and 5th",
            "Single and double battements frappés",
            "Fondu movements",
            "Développé and demi-rond de jambe",
            "Relevés devant · derrière and passé",
            "Adage with 1st · 2nd and 3rd arabesques both sides",
            "Single relevé pirouette en dehors",
            "Glissades devant and derrière soutenu",
            "Sissonnes en avant fermées",
            "Temps levé chassé pas de bourrée",
            "Coupé chassé temps levé round the room",
            "Soutenu turns en dedans on the diagonal",
            "Batterie: échappé sauté closing with a beat",
            "Classical solo up to one minute"
          ]),
          rank({"Grade %{n}", 5}, nil, 0, [], [
            "Petits battements at the barre",
            "Développé with grand rond de jambe en l'air",
            "Battements balancés",
            "Grand plié · développé and demi-rond in the centre",
            "4th and 5th arabesques",
            "Pirouette en dehors and pirouette en dedans",
            "Changements and soubresauts",
            "Glissade assemblé",
            "Sissonne en avant ouverte and en arrière fermée",
            "Entrechat quatre",
            "Jeté en attitude devant round the room",
            "Balancé en tournant",
            "Petits tours on the diagonal both sides",
            "Unseen enchaînement of up to 3 steps"
          ]),
          rank({"Grade %{n}", 6}, nil, 0, [], [
            "Knows effacée · attitudes and five movements of the foot",
            "Battements dégagés with piqués",
            "Grands battements and frappés en croix",
            "Deux grands ronds de jambe en l'air avec arabesque",
            "Attitudes with pirouette en dedans",
            "Pirouette en dehors from 4th position",
            "Échappés sautés with pas de bourrée dessous",
            "Pas de bourrée couru",
            "Demi-contretemps and assemblé élancé on the diagonal",
            "Grands jetés en tournant",
            "Posé tours and petits tours on the diagonal",
            "Entrechat royale and entrechat trois",
            "Unseen enchaînement of up to 4 steps"
          ]),
          rank({:exam, "Intermediate Foundation"}, nil, 0, [], [
            "Theory: positions · seven movements · eight directions · five arabesques",
            "Uses the eight fixed points of the room",
            "Full traditional barre from pliés to relevés",
            "Adage with attitude and grand rond de jambe en l'air",
            "Pirouettes en dedans and en dehors from 4th",
            "Brisé dessus soutenu",
            "Entrechat trois derrière and devant",
            "Glissade jeté and jeté temps levé",
            "Grands jetés en tournant both sides",
            "Posé tours en dedans or petits tours on the diagonal",
            "Pointe (girls): flexing · rises · échappés relevés",
            "Boys option: grands changements and échappés battus",
            "Classical solo up to one minute (not on pointe)"
          ]),
          rank({:exam, "Intermediate"}, nil, 0, [], [
            "Theory of port de bras and correct movements of the foot",
            "Ronds de jambe en l'air and fouettés à terre",
            "Grand fouetté and développé en tournant",
            "Preparation for fouettés rond de jambe en tournant",
            "Grande préparation and pirouettes en dehors from 4th",
            "Pirouettes en dedans from a lunge and from 4th",
            "Ballonné simple and écarté",
            "Échappé battu beating out and in",
            "Pas de bourrée en tournant en dehors and en dedans",
            "Entrechat quatre and royale combinations",
            "Cabriole devant ouverte",
            "Grand jeté en tournant to posé in 2nd arabesque",
            "Petits pas de basque en tournant",
            "Pointe: pas de bourrée piqués · couru · posés coupés and emboîtés",
            "Boys: tour en l'air from changement and from relevé"
          ]),
          rank({:exam, "Advanced 1"}, nil, 0, [], [
            "Traditional and additional barre including battements jetés at 45°",
            "Adage study and jetés of adage",
            "Arabesque penchée",
            "Promenades in arabesque · attitude and 2nd",
            "Cinq relevés · pas de chaconne · temps de courante",
            "Pirouettes en dedans in attitude or arabesque",
            "Pirouettes en dehors with extension en l'air",
            "Fouettés rond de jambe en tournant",
            "Entrechat cinq and brisé dessous",
            "Cabriole derrière and jeté battu à la seconde",
            "Sissonnes battues and temps de cuisse",
            "Ballonné à trois temps",
            "Pointe: soutenu turns · posé tours · posé développé",
            "Boys: double tour en l'air and tours à la seconde"
          ]),
          rank({:exam, "Advanced 2"}, nil, 0, [], [
            "Full traditional barre with option A or B additions",
            "Battements tendus with dégagé en tournant",
            "Advanced adages from the Cecchetti days of the week",
            "Grands jetés en attitude and à la seconde",
            "Entrechat six and entrechat six de côté",
            "Assemblé Cecchetti",
            "Jeté double rond de jambe sauté en avant and en arrière",
            "Sissonnes retombées with entrechat six",
            "Jeté fouetté sauté en tournant",
            "Coupé jeté en tournant round the room",
            "Douze jetés en tournant and petits tours both sides",
            "Pointe: advanced enchaînements on softened blocked shoes",
            "Classical solo (tutu optional)"
          ])
        ]
      ),
      template(
        "ballet_vaganova",
        "Ballet (Vaganova method)",
        "ballet",
        "level",
        :federation,
        "Vaganova 8-year programme (yearly content reconstructed)",
        [
          rank("Year 1", nil, 0, [], [
            "Five positions of the feet and preparatory arm position",
            "Demi-plié and grand plié facing the barre",
            "Battement tendu and tendu jeté",
            "Rond de jambe par terre en dehors and en dedans",
            "Sur le cou-de-pied positions",
            "Battement frappé and battement fondu (basic)",
            "Relevé on demi-pointe in 1st · 2nd and 5th",
            "Grand battement jeté",
            "Port de bras 1st and 2nd",
            "Épaulement croisé and effacé introduced",
            "Temps lié par terre",
            "Sauté in 1st · 2nd and 5th",
            "Changement de pieds and échappé sauté",
            "Pointe (girls): relevés in 1st and 2nd facing the barre"
          ]),
          rank("Year 2", nil, 0, [], [
            "Barre exercises sideways to the barre en croix",
            "Rond de jambe en l'air",
            "Petit battement sur le cou-de-pied",
            "Battement développé to 90°",
            "Double frappé",
            "Port de bras 3rd",
            "Small poses croisée · effacée · écartée",
            "1st to 4th arabesques",
            "Preparation for pirouettes (quarter and half turns)",
            "Assemblé and glissade",
            "Sissonne simple and sissonne fermée",
            "Pas de chat and jeté",
            "Pas de bourrée with change of feet",
            "Pointe: échappé · pas de bourrée suivi in the centre"
          ]),
          rank("Year 3", nil, 0, [], [
            "Grand rond de jambe jeté",
            "Flic-flac",
            "Battement développé in big poses",
            "Port de bras 4th",
            "Single pirouette en dehors and en dedans from 5th and 2nd",
            "Pas de basque",
            "Sissonne ouverte at 45°",
            "Entrechat quatre · royale and trois",
            "Grand changement de pieds",
            "Pas de chat and petit jeté combinations",
            "Pas couru",
            "Pointe: tours chaînés and pas de bourrée en tournant"
          ]),
          rank("Year 4", nil, 0, [], [
            "Pirouette from 4th en dehors and en dedans",
            "Double pirouettes from 5th",
            "Preparation for tours in big poses",
            "Fouetté at 45°",
            "Renversé (preparatory)",
            "Entrechat cinq",
            "Brisé",
            "Cabriole at 45°",
            "Grand jeté in 1st arabesque",
            "Sissonne tombée",
            "Pointe: tours piqués and beaten steps on pointe"
          ]),
          rank("Year 5", nil, 0, [], [
            "Tours in big poses (attitude and arabesque)",
            "Double tours from 4th",
            "Tours chaînés on demi-pointe and pointe",
            "Grand fouetté (adagio)",
            "Jeté entrelacé",
            "Saut de basque",
            "Cabriole at 90°",
            "Entrechat six",
            "Grand assemblé en tournant",
            "Boys: single tour en l'air",
            "Pointe: tours from 5th and from 4th"
          ]),
          rank("Year 6", nil, 0, [], [
            "Renversé en dehors and en dedans",
            "Grand fouetté en tournant",
            "Double tours in big poses",
            "Fouettés en tournant (8-16)",
            "Grand sissonne renversée",
            "Double assemblé (boys)",
            "Boys: double tour en l'air",
            "Jeté en tournant in series",
            "Pointe: tours in big poses on pointe",
            "Duet class basics (supported pirouettes)"
          ]),
          rank("Year 7", nil, 0, [], [
            "Multiple pirouettes (3+) en dehors and en dedans",
            "32 fouettés en tournant (girls)",
            "Grandes pirouettes à la seconde (boys)",
            "Entrechat huit and brisé dessus-dessous",
            "Revoltade and double cabriole (boys)",
            "Grand allegro combinations across the floor",
            "Pas de deux: lifts and supported adagio",
            "Character and historical dance styles",
            "Classical variation from repertoire"
          ]),
          rank("Year 8", nil, 0, [], [
            "Full virtuoso class at professional tempo",
            "Multiple tours in big poses and fouettés with doubles",
            "Manège of piqués or jetés en tournant",
            "Coda-level grand allegro",
            "Pas de deux with full lifts and fish dives",
            "Two repertoire variations performed",
            "Final state examination class",
            "Stage performance in a full ballet"
          ])
        ]
      ),
      template(
        "kizomba_levels",
        "Kizomba",
        "dance",
        "level",
        :palee,
        "Palee levels (no examining body)",
        [
          rank("Level 1 · Foundations", nil, 0, [], [
            "Finds the main beat in kizomba music",
            "Closed embrace (abraço) with relaxed frame",
            "Weight transfer on every step",
            "Musical walk forward and back",
            "Basic step (passo básico) in place",
            "Side step (passo lateral)",
            "Basic step forward and back",
            "Leader's exit (saída) to the side",
            "Lead and follow through the chest",
            "Pause and restart on the beat"
          ]),
          rank("Level 2 · Improver", nil, 0, [], [
            "Saída da dama (follower's exit)",
            "Retrocesso (backward walk of the follower)",
            "Vírgula",
            "3x3 (three-by-three) pattern",
            "Balance (balanço) in place",
            "Basic pivots in closed hold",
            "Simple follower turn and return to embrace",
            "Corridinha (small running steps)",
            "Navigation on a social floor without collisions",
            "Dances a full song without losing the beat"
          ]),
          rank("Level 3 · Intermediate", nil, 0, [], [
            "Cruzado (cross step) for leader and follower",
            "Around the world",
            "Foot swipe (rasteira)",
            "Opening to open hold and closing again",
            "Double-time steps (contratempo) on the leader cue",
            "Linked combinations of 4+ figures",
            "Follower hip and body styling (ginga)",
            "Leader body isolation to signal changes",
            "Musicality: stops and breaks in the song",
            "Dances with partners of different levels"
          ]),
          rank("Level 4 · Advanced", nil, 0, [], [
            "Kota and semba-rooted steps",
            "Multiple follower turns with clean finish",
            "Shadow position walks and exits",
            "Tarraxinha slow isolations",
            "Urban kiz basics: lines and freezes",
            "Improvises fully led sequences",
            "Interprets melody and percussion layers",
            "Leads or follows both roles at basic level",
            "Smooth recovery from mis-leads"
          ]),
          rank("Level 5 · Master", nil, 0, [], [
            "Signature style with own variations",
            "Semba · kizomba · urban kiz switching in one song",
            "Dynamic contrast: slow motion and fast footwork",
            "Choreographed couple routine of 2+ minutes",
            "Assists teaching a beginner class",
            "Gives clear connection feedback to partners"
          ])
        ]
      ),
      template(
        "dance_fitness_levels",
        "Zumba / dance fitness",
        "dance_fitness",
        "level",
        :palee,
        "Palee levels for dance fitness classes",
        [
          rank("Starter", nil, 0, [], [
            "Follows the instructor's visual cues",
            "Merengue march and side-to-side step",
            "Salsa basic step forward and back",
            "Cumbia tap step with arm sway",
            "Reggaeton tap and lean step",
            "Low-impact options for each move",
            "Completes 30 minutes of class",
            "Hydration and self-monitoring of intensity"
          ]),
          rank("Core Rhythms", nil, 0, [], [
            "Merengue with arms and travelling",
            "Salsa side basic and cross-body styling",
            "Cumbia with turns",
            "Reggaeton bounce and body roll",
            "Recognises verse · chorus and bridge of a song",
            "Changes moves on the musical phrase (8-count)",
            "Completes a full 60-minute class"
          ]),
          rank("World Rhythms", nil, 0, [], [
            "Bachata basic with hip motion",
            "Cha-cha chassé",
            "Samba bounce and samba walks",
            "Soca jump and wine",
            "Bhangra shoulder bounce",
            "Belly dance hip shimmy",
            "Hip-hop groove and step touch",
            "Learns a new song routine in one class"
          ]),
          rank("High Energy", nil, 0, [], [
            "High-impact jumps on every peak song",
            "Squat and lunge toning tracks with good form",
            "Full class at high intensity without breaks",
            "Clean timing on fast tempo (140+ bpm)",
            "Knows 10+ class routines from memory",
            "Adds own styling and energy to moves"
          ]),
          rank("Leader", nil, 0, [], [
            "Demonstrates moves in mirror image",
            "Gives non-verbal cues one count early",
            "Leads one full song for the group",
            "Builds a routine on verse-chorus structure",
            "Offers modifications for beginners"
          ])
        ]
      ),
      template(
        "aerial_yoga_levels",
        "Aerial hammock / aerial yoga",
        "pole_aerial",
        "level",
        :palee,
        "Palee levels (no body grades students)",
        [
          rank("Intro", nil, 0, [], [
            "Sets hammock height for seated and standing work",
            "Safe mount into seat and safe exit",
            "Supported standing postures (warrior · tree)",
            "Hammock-supported forward fold",
            "Swinging seat and cocoon relaxation",
            "Supported back bend over the hammock",
            "Feet-on-floor assisted inversion"
          ]),
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Basic invert (bat) from seat with control",
            "Straddle inversion repeated 3 times",
            "Diamond leg inversion",
            "Gazelle",
            "Butterfly",
            "Buddha (lotus) inverted",
            "Thigh lock",
            "Double knee hook (diaper) wrap",
            "Shoulder stand variation",
            "Comes out of every invert slowly to the floor"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Pullover from standing into front balance",
            "Swan pose",
            "Pullover 3-5 times in a row",
            "Hip key",
            "Cross back straddle entry",
            "Higher inversions above the hammock seat",
            "Back walkover off the hammock",
            "Bomb drop",
            "Waterfall",
            "Linked sequence of 4 poses without touching the floor"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Climb into the hammock from the floor",
            "Hip key to inverted splits",
            "Inverted crucifix",
            "Star drop",
            "Pinwheel or rollover sequence",
            "Spinning poses with controlled momentum",
            "Choreographed 2-minute routine"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Dynamic drops linked into flows",
            "One-arm and one-leg holds",
            "Inverted strength skills (e.g. straddle-up without kick)",
            "Performance routine of 3+ minutes",
            "Spots and cues a beginner safely"
          ])
        ]
      )
    ]
  end
end
