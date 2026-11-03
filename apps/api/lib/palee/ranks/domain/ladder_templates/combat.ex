defmodule Palee.Ranks.Domain.LadderTemplates.Combat do
  @moduledoc "Template ladders: Martial arts and combat sports (ADR-400; sources in docs/research/rank-curricula-research-2026-11-03.md)."

  import Palee.Ranks.Domain.LadderTemplates.Build

  def all do
    [
      template(
        "bjj_adult",
        "BJJ belts",
        "bjj_grappling",
        "belt",
        :federation,
        "IBJJF adult belts (16+)",
        [
          rank("White", "white", 4, [], ["Tapping and mat etiquette"]),
          rank("Blue", "blue", 4, [], [
            "Break-falls back and to the side",
            "Shrimp and bridge escapes to both sides",
            "Closed guard posture and guard break",
            "Mount escape with upa and elbow-knee",
            "Side control escape to guard",
            "Scissor sweep and hip-bump sweep",
            "Armbar and triangle from closed guard",
            "Rear naked choke from back control",
            "Knee-cut or toreando guard pass",
            "Double-leg or single-leg takedown",
            "Positional sparring with control"
          ]),
          rank("Purple", "purple", 4, [days: 730], [
            "Open guard retention (De La Riva or spider)",
            "Half guard sweeps (old school and deep half)",
            "Butterfly guard sweeps and elevations",
            "Three guard passes chained together",
            "Back take from turtle and seatbelt control",
            "Collar chokes from mount and back",
            "Kimura and americana from top and bottom",
            "Live rolls with a clear game plan"
          ]),
          rank("Brown", "brown", 4, [days: 540], [
            "Connected attacks from a personal guard game",
            "Leg-lock entries and straight ankle lock",
            "Counters to the common guard passes",
            "Pressure passing and smash half guard",
            "Omoplata and wrist lock",
            "Helps teach white belts"
          ]),
          rank("Black", "black", 6, [days: 365], [
            "A complete game in every position",
            "Chains submissions and transitions fluidly",
            "Heel hook defence and no-gi adaptations",
            "Competition-level takedowns",
            "Can teach the whole curriculum",
            "Age 19 or older (IBJJF)"
          ])
        ]
      ),
      template(
        "bjj_kids",
        "BJJ kids belts",
        "bjj_grappling",
        "belt",
        :federation,
        "IBJJF kids system (ages 4 to 15)",
        [
          rank("White", "white", 4, [], ["Tapping and mat etiquette"]),
          rank("Grey-white", "grey", 4, [], [
            "Safe backward break-fall",
            "Shrimp and bridge",
            "Technical stand-up"
          ]),
          rank("Grey", "grey", 4, [], [
            "Hold side control for 10 seconds",
            "Mount escape with upa",
            "Closed guard posture in both roles"
          ]),
          rank("Grey-black", "grey", 4, [], [
            "Scissor sweep",
            "Armbar from mount",
            "Side control escape to guard"
          ]),
          rank("Yellow-white", "yellow", 4, [], [
            "Hip-bump sweep",
            "Guard pass to side control",
            "Knee on belly"
          ]),
          rank("Yellow", "yellow", 4, [], [
            "Triangle from closed guard",
            "Back control with hooks",
            "Double-leg takedown"
          ]),
          rank("Yellow-black", "yellow", 4, [], [
            "Back control escape",
            "Kimura from guard",
            "Butterfly sweep"
          ]),
          rank("Orange-white", "orange", 4, [], [
            "Collar choke from mount",
            "Half guard sweep",
            "Turtle defence"
          ]),
          rank("Orange", "orange", 4, [], [
            "Sweep to submission combination",
            "Two guard passes",
            "Osoto-gari or single-leg takedown"
          ]),
          rank("Orange-black", "orange", 4, [], [
            "Omoplata",
            "Back take from turtle",
            "Positional sparring with a plan"
          ]),
          rank("Green-white", "green", 4, [], [
            "Open guard retention",
            "Bow and arrow choke",
            "Counter to a guard pass"
          ]),
          rank("Green", "green", 4, [], [
            "Three attacks chained from guard",
            "Straight ankle lock (allowed for the age)",
            "Helps younger children drill"
          ]),
          rank("Green-black", "green", 4, [], [
            "Whole kids curriculum in live sparring",
            "Ready for the adult blue belt at 16"
          ])
        ]
      ),
      template(
        "karate_kyu",
        "Karate belts",
        "karate",
        "belt",
        :federation,
        "Common 7-belt kyu ladder",
        [
          rank("White", "white", 0, [], ["Dojo etiquette (rei and seiza)"]),
          rank("Yellow", "yellow", 0, [], [
            "Stances zenkutsu and kiba-dachi",
            "Oi-zuki and gyaku-zuki",
            "Age-uke and gedan-barai",
            "Mae-geri",
            "First kata (Taikyoku or Heian Shodan)"
          ]),
          rank("Orange", "orange", 0, [], [
            "Kokutsu-dachi and shuto-uke",
            "Soto-uke and uchi-uke",
            "Mawashi-geri",
            "Gohon kumite (five-step sparring)",
            "Heian Nidan"
          ]),
          rank("Green", "green", 0, [], [
            "Yoko-geri keage and kekomi",
            "Combinations of three techniques",
            "Sanbon kumite (three-step sparring)",
            "Heian Sandan"
          ]),
          rank("Blue", "blue", 0, [], [
            "Ushiro-geri",
            "Kihon ippon kumite",
            "Heian Yondan and Godan"
          ]),
          rank("Brown", "brown", 0, [], [
            "Jiyu ippon kumite",
            "Tekki Shodan and Bassai Dai",
            "Controlled free sparring (jiyu kumite)"
          ]),
          rank("Black", "black", 0, [days: 365], [
            "All kihon with power and control",
            "A senior kata of choice with bunkai",
            "Free sparring against two opponents in turn"
          ])
        ]
      ),
      template(
        "karate_shotokan_kyu",
        "Shotokan karate kyu",
        "karate",
        "belt",
        :federation,
        "JKA-style 10 kyu to shodan",
        [
          rank({"Kyu %{n}", 10}, "white", 0, [], ["Dojo etiquette and dojo kun"]),
          rank({"Kyu %{n}", 9}, "yellow", 0, [days: 90], [
            "Zenkutsu-dachi with oi-zuki",
            "Age-uke soto-uke and gedan-barai",
            "Mae-geri keage",
            "Kata Heian Shodan"
          ]),
          rank({"Kyu %{n}", 8}, "orange", 0, [days: 90], [
            "Uchi-uke and shuto-uke in kokutsu-dachi",
            "Mawashi-geri",
            "Gohon kumite jodan and chudan",
            "Kata Heian Nidan"
          ]),
          rank({"Kyu %{n}", 7}, "red", 0, [days: 90], [
            "Yoko-geri keage and kekomi in kiba-dachi",
            "Kizami-zuki and gyaku-zuki combination",
            "Sanbon kumite",
            "Kata Heian Sandan"
          ]),
          rank({"Kyu %{n}", 6}, "green", 0, [days: 90], [
            "Ushiro-geri",
            "Kihon ippon kumite",
            "Kata Heian Yondan"
          ]),
          rank({"Kyu %{n}", 5}, "purple", 0, [days: 90], [
            "Combinations with stance changes",
            "Kihon ippon kumite with counter",
            "Kata Heian Godan"
          ]),
          rank({"Kyu %{n}", 4}, "purple", 0, [days: 90], [
            "Mawashi-geri and ura-mawashi-geri",
            "Jiyu ippon kumite",
            "Kata Tekki Shodan"
          ]),
          rank({"Kyu %{n}", 3}, "brown", 0, [days: 180], [
            "Kihon with hip rotation and kime",
            "Jiyu ippon kumite on all levels",
            "Kata Bassai Dai"
          ]),
          rank({"Kyu %{n}", 2}, "brown", 1, [days: 180], [
            "Controlled jiyu kumite",
            "Kata Kanku Dai or Jion"
          ]),
          rank({"Kyu %{n}", 1}, "brown", 2, [days: 180], [
            "Jiyu kumite with timing and distance",
            "Kata Enpi or Jitte with bunkai"
          ]),
          rank({"Dan %{n}", 1}, "black", 0, [days: 365], [
            "All kihon with kime",
            "Tokui kata (own choice) and a set kata",
            "Jiyu kumite"
          ])
        ]
      ),
      template(
        "karate_kyokushin_kyu",
        "Kyokushin karate kyu",
        "karate",
        "belt",
        :federation,
        "Kyokushin colours (orange blue yellow green brown)",
        [
          rank("White", "white", 0, [], ["Dojo etiquette and seiza"]),
          rank({"Kyu %{n}", 10}, "orange", 0, [days: 90], [
            "Seiken and uraken strikes",
            "Mae-geri and hiza-geri",
            "Kata Taikyoku Sono Ichi"
          ]),
          rank({"Kyu %{n}", 9}, "orange", 1, [days: 90], [
            "Mawashi-geri gedan and chudan",
            "Basic blocks in zenkutsu-dachi",
            "Kata Taikyoku Sono Ni and San"
          ]),
          rank({"Kyu %{n}", 8}, "blue", 0, [days: 90], [
            "Yoko-geri and kakato-geri",
            "Kata Pinan Sono Ichi",
            "Light kumite rounds"
          ]),
          rank({"Kyu %{n}", 7}, "blue", 1, [days: 90], [
            "Combination punching on pads",
            "Kata Pinan Sono Ni"
          ]),
          rank({"Kyu %{n}", 6}, "yellow", 0, [days: 120], [
            "Ushiro-geri",
            "Kata Pinan Sono San and Sanchin",
            "Full-contact kumite (two rounds)"
          ]),
          rank({"Kyu %{n}", 5}, "yellow", 1, [days: 120], [
            "Kata Pinan Sono Yon",
            "Conditioning: 50 push-ups on knuckles"
          ]),
          rank({"Kyu %{n}", 4}, "green", 0, [days: 180], [
            "Jodan mawashi-geri",
            "Kata Pinan Sono Go and Gekisai Dai",
            "Kumite five rounds"
          ]),
          rank({"Kyu %{n}", 3}, "green", 1, [days: 180], [
            "Kata Tsuki no Kata and Yantsu",
            "Tameshiwari (breaking) when the club tests it"
          ]),
          rank({"Kyu %{n}", 2}, "brown", 0, [days: 180], [
            "Kata Saiha and Tensho",
            "Kumite eight rounds"
          ]),
          rank({"Kyu %{n}", 1}, "brown", 1, [days: 180], [
            "Kata Gekisai Sho and Bassai Dai",
            "Helps teach the junior grades"
          ]),
          rank({"Dan %{n}", 1}, "black", 0, [days: 365], [
            "All kyu kata and kihon",
            "Kumite of 10 or more rounds"
          ])
        ]
      ),
      template(
        "judo_kyu",
        "Judo belts",
        "judo",
        "belt",
        :federation,
        "IJF/European kyu colours (6 kyu to shodan)",
        [
          rank("White", "white", 0, [], ["Bow (rei) and judogi care", "Ukemi back and side"]),
          rank("Yellow", "yellow", 0, [days: 90], [
            "Ukemi forward rolling",
            "O-soto-gari and o-goshi",
            "Hiza-guruma and de-ashi-barai",
            "Kesa-gatame and escape",
            "Kumikata (grips) and tsukuri"
          ]),
          rank("Orange", "orange", 0, [days: 120], [
            "Ippon-seoi-nage and tai-otoshi",
            "O-uchi-gari and ko-uchi-gari",
            "Yoko-shiho-gatame and kami-shiho-gatame",
            "Randori standing and on the ground"
          ]),
          rank("Green", "green", 0, [days: 180], [
            "Harai-goshi and uchi-mata",
            "Combination throws (renraku-waza)",
            "Turnovers into hold-downs",
            "Juji-gatame (age 13 or older)"
          ]),
          rank("Blue", "blue", 0, [days: 180], [
            "Counter throws (kaeshi-waza)",
            "Sankaku and shime-waza (age 16 or older)",
            "Nage-no-kata first set"
          ]),
          rank("Brown", "brown", 0, [days: 270], [
            "Sumi-gaeshi and tomoe-nage",
            "Tokui-waza in randori",
            "Nage-no-kata three sets"
          ]),
          rank("Black", "black", 0, [days: 365], [
            "Nage-no-kata complete",
            "Katame-no-kata",
            "Competition or shiai points as the federation requires",
            "Age 15 or older"
          ])
        ]
      ),
      template(
        "taekwondo_geup",
        "Taekwondo belts",
        "taekwondo",
        "belt",
        :federation,
        "World Taekwondo/Kukkiwon 10 geup to 1st dan/poom",
        [
          rank({"Geup %{n}", 10}, "white", 0, [], ["Dojang etiquette and stances"]),
          rank({"Geup %{n}", 9}, "white", 1, [days: 60], [
            "Ap seogi and ap kubi",
            "Momtong jireugi and arae makki",
            "Ap chagi"
          ]),
          rank({"Geup %{n}", 8}, "yellow", 0, [days: 60], [
            "Poomsae Taegeuk Il Jang",
            "Bandal chagi"
          ]),
          rank({"Geup %{n}", 7}, "yellow", 1, [days: 60], [
            "Poomsae Taegeuk Ee Jang",
            "Yeop chagi"
          ]),
          rank({"Geup %{n}", 6}, "green", 0, [days: 90], [
            "Poomsae Taegeuk Sam Jang",
            "Dollyeo chagi to body and head",
            "Step sparring"
          ]),
          rank({"Geup %{n}", 5}, "green", 1, [days: 90], ["Poomsae Taegeuk Sa Jang", "Dwi chagi"]),
          rank({"Geup %{n}", 4}, "blue", 0, [days: 90], [
            "Poomsae Taegeuk Oh Jang",
            "Kyorugi with protectors"
          ]),
          rank({"Geup %{n}", 3}, "blue", 1, [days: 90], [
            "Poomsae Taegeuk Yuk Jang",
            "Naeryeo chagi"
          ]),
          rank({"Geup %{n}", 2}, "red", 0, [days: 120], [
            "Poomsae Taegeuk Chil Jang",
            "Spinning kicks (dwi huryeo chagi)"
          ]),
          rank({"Geup %{n}", 1}, "red", 1, [days: 120], [
            "Poomsae Taegeuk Pal Jang",
            "Board breaking"
          ]),
          rank({"Dan %{n}", 1}, "black", 0, [days: 180], [
            "All Taegeuk poomsae and Koryo",
            "Kyorugi and self-defence (hosinsul)",
            "Poom instead of dan under age 15 (Kukkiwon)"
          ])
        ]
      ),
      template(
        "aikido_kyu",
        "Aikido kyu",
        "martial_arts",
        "belt",
        :federation,
        "Aikikai Hombu (practice days per grade)",
        [
          rank({"Kyu %{n}", 6}, "white", 0, [], ["Ukemi forward and backward"]),
          rank({"Kyu %{n}", 5}, "white", 0, [classes: 30], [
            "Shomen-uchi ikkyo omote and ura",
            "Katate-dori shiho-nage",
            "Shomen-uchi irimi-nage",
            "Tai no henko and kokyu-dosa"
          ]),
          rank({"Kyu %{n}", 4}, "white", 0, [classes: 40], [
            "Shomen-uchi nikyo and sankyo",
            "Chudan-tsuki kote-gaeshi",
            "Ryote-dori tenchi-nage"
          ]),
          rank({"Kyu %{n}", 3}, "white", 0, [classes: 50], [
            "Yokomen-uchi shiho-nage and irimi-nage",
            "Shomen-uchi yonkyo",
            "Ushiro ryote-dori kote-gaeshi"
          ]),
          rank({"Kyu %{n}", 2}, "white", 0, [classes: 50], [
            "Ushiro waza from several grabs",
            "Suwari-waza ikkyo to yonkyo",
            "Hanmi handachi shiho-nage"
          ]),
          rank({"Kyu %{n}", 1}, "white", 0, [classes: 60], [
            "Jiyu-waza against one attacker",
            "Tanto-dori basics"
          ]),
          rank({"Dan %{n}", 1}, "black", 0, [classes: 70], [
            "Randori against two attackers",
            "All kyu techniques fluidly"
          ])
        ]
      ),
      template(
        "muay_thai_khan",
        "Muay Thai khan",
        "muay_thai",
        "level",
        :federation,
        "Khan grading with prajied (Kru Muay Thai Association style)",
        [
          rank({"Khan %{n}", 1}, "white", 0, [], [
            "Fighting stance and footwork",
            "Jab cross hook uppercut",
            "Wai kru ram muay respect"
          ]),
          rank({"Khan %{n}", 2}, "yellow", 0, [days: 90], [
            "Teep (front kick) both legs",
            "Roundhouse kick to body both sides",
            "Check (block) a low kick"
          ]),
          rank({"Khan %{n}", 3}, "yellow", 0, [days: 90], [
            "Straight knee and diagonal knee",
            "Horizontal and upward elbows",
            "Combinations of four on pads"
          ]),
          rank({"Khan %{n}", 4}, "green", 0, [days: 120], [
            "Clinch entry and neck control",
            "Catch a kick and counter",
            "Technical sparring three rounds"
          ]),
          rank({"Khan %{n}", 5}, "green", 0, [days: 120], [
            "Switch kick and switch knee",
            "Clinch knees and off-balancing",
            "Teep defence and counter"
          ]),
          rank({"Khan %{n}", 6}, "blue", 0, [days: 180], [
            "Spinning elbow and back elbow",
            "Sweeps from the catch",
            "Sparring five rounds"
          ]),
          rank({"Khan %{n}", 7}, "blue", 0, [days: 180], [
            "Ram muay performed in full",
            "Feints and rhythm changes"
          ]),
          rank({"Khan %{n}", 8}, "brown", 0, [days: 180], [
            "Ring craft and cutting off the ring",
            "Holds pads for others"
          ]),
          rank({"Khan %{n}", 9}, "brown", 0, [days: 365], [
            "Interclub bout or full sparring test",
            "Explains the history of Muay Thai"
          ]),
          rank({"Khan %{n}", 10}, "red", 0, [days: 365], [
            "Assists teaching a class",
            "Builds a pad round for a beginner"
          ])
        ]
      ),
      template(
        "kickboxing_wako",
        "Kickboxing belts",
        "kickboxing",
        "belt",
        :federation,
        "WAKO optional grading syllabus (2025)",
        [
          rank("White", "white", 0, [], ["Guard stance and footwork"]),
          rank("Yellow", "yellow", 0, [days: 180], [
            "Jab cross hook uppercut",
            "Front kick and roundhouse kick",
            "Parry and block straight punches"
          ]),
          rank("Orange", "orange", 0, [days: 180], [
            "Side kick and low kick",
            "Slip and roll under punches",
            "Three-technique combinations"
          ]),
          rank("Green", "green", 0, [days: 180], [
            "Hook kick and axe kick",
            "Counter-attacks after defence",
            "Light sparring two rounds"
          ]),
          rank("Blue", "blue", 0, [days: 240], [
            "Spinning back kick",
            "Kick catching defence",
            "Sparring three rounds in point or light contact"
          ]),
          rank("Brown", "brown", 0, [days: 365], [
            "Jumping and spinning kicks",
            "Ring and tatami tactics",
            "Rules of WAKO disciplines"
          ]),
          rank("Black", "black", 0, [days: 365], [
            "Full technical exam of all colours",
            "Sparring several rounds against fresh opponents",
            "Age 16 or older"
          ])
        ]
      ),
      template(
        "boxing_awards",
        "Boxing levels",
        "boxing",
        "level",
        :federation,
        "Modelled on England Boxing awards (3 non-contact + 3 contact)",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Stance and guard",
            "Step forward back and sideways",
            "Jab to the head and body"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Cross and lead hook",
            "Parry and block the jab",
            "Shadow boxing one round"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Uppercuts both hands",
            "Slip and roll",
            "Four-punch combinations on pads"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Conditioned sparring (one hand or set attack)",
            "Counter-punching after defence"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Technical sparring two rounds",
            "Ring craft: angles and the ropes"
          ]),
          rank({"Level %{n}", 6}, nil, 0, [], [
            "Full sparring three rounds",
            "Knows amateur boxing rules and scoring"
          ])
        ]
      ),
      template(
        "mma_levels",
        "MMA levels",
        "mma",
        "level",
        :palee,
        "Gym progression (no federation ranks)",
        [
          rank({"Level %{n}", 1}, nil, 0, [], [
            "Stance and footwork for striking",
            "Basic punches and kicks",
            "Break-falls and shrimping"
          ]),
          rank({"Level %{n}", 2}, nil, 0, [], [
            "Double-leg and single-leg takedowns",
            "Sprawl and takedown defence",
            "Guard and mount escapes"
          ]),
          rank({"Level %{n}", 3}, nil, 0, [], [
            "Cage wall work (pin and escape)",
            "Ground and pound from guard and mount",
            "Rear naked choke and guillotine"
          ]),
          rank({"Level %{n}", 4}, nil, 0, [], [
            "Striking to takedown chains",
            "Getting up from bottom position",
            "MMA sparring with light contact"
          ]),
          rank({"Level %{n}", 5}, nil, 0, [], [
            "Full MMA sparring three rounds",
            "Game plan for an amateur bout",
            "Knows the unified rules"
          ])
        ]
      ),
      template(
        "krav_maga_grades",
        "Krav Maga grades (P G E)",
        "krav_maga",
        "level",
        :federation,
        "IKMF/KMG Practitioner Graduate Expert patches",
        [
          rank("P1", nil, 0, [], [
            "Fighting stance and movement",
            "Straight punches palm strikes and front kick",
            "360 outside defence",
            "Release from front choke"
          ]),
          rank("P2", nil, 0, [], [
            "Elbows and knees",
            "Inside defences against punches",
            "Choke releases from behind and side",
            "Break-falls"
          ]),
          rank("P3", nil, 0, [], [
            "Defences against hooks and uppercuts",
            "Bear hug releases",
            "Ground fighting basics"
          ]),
          rank("P4", nil, 0, [], [
            "Defence against kicks",
            "Headlock releases",
            "Fighting under stress drills"
          ]),
          rank("P5", nil, 0, [], [
            "Knife threat defences (static)",
            "Stick attack defences",
            "Multiple attacker awareness"
          ]),
          rank("G1", nil, 0, [], [
            "Knife attack defences (overhead and stab)",
            "Gun threat from front",
            "Third-party protection basics"
          ]),
          rank("G2", nil, 0, [], ["Gun threats from side and behind", "Advanced ground defences"]),
          rank("G3", nil, 0, [], [
            "Knife and stick combined scenarios",
            "Defending while seated or in a vehicle"
          ]),
          rank("G4", nil, 0, [], ["Long-gun and rifle threats", "Fighting several attackers"]),
          rank("G5", nil, 0, [], [
            "All practitioner and graduate syllabi under stress",
            "Scenario training in low light"
          ]),
          rank("E1", "black", 0, [], [
            "Expert exam: complete syllabus at speed",
            "Endurance fight test"
          ])
        ]
      ),
      template(
        "krav_maga_belts",
        "Krav Maga belts",
        "krav_maga",
        "belt",
        :federation,
        "Lichtenfeld/KMW/FEKM colour belts",
        [
          rank("White", "white", 0, [], ["Fighting stance and safety rules"]),
          rank("Yellow", "yellow", 0, [days: 90], [
            "Punches palm strikes elbows knees",
            "Front and round kicks",
            "360 outside defence and inside defences",
            "Choke releases front side and back"
          ]),
          rank("Orange", "orange", 0, [days: 180], [
            "Defences against hooks and kicks",
            "Bear hug and headlock releases",
            "Ground escapes from mount and guard"
          ]),
          rank("Green", "green", 0, [days: 270], [
            "Knife threat and stab defences",
            "Stick defences",
            "Fighting from the ground to standing"
          ]),
          rank("Blue", "blue", 0, [days: 365], [
            "Handgun threats from all angles",
            "Multiple attacker drills"
          ]),
          rank("Brown", "brown", 0, [days: 365], [
            "Rifle threats and third-party protection",
            "Scenario and stress tests"
          ]),
          rank("Black", "black", 0, [days: 365], [
            "Complete syllabus under fatigue",
            "Teaching ability"
          ])
        ]
      ),
      template(
        "kung_fu_sash",
        "Kung fu sashes",
        "kung_fu",
        "belt",
        :federation,
        "Common school sash ladder (styles vary)",
        [
          rank("White", "white", 0, [], ["Horse stance bow stance cat stance"]),
          rank("Yellow", "yellow", 0, [days: 90], [
            "Basic punches palms and blocks",
            "Front snap and side kicks",
            "First form of the school"
          ]),
          rank("Orange", "orange", 0, [days: 90], [
            "Stance transitions with balance",
            "Sweeps and low stances (pu bu)",
            "Second form"
          ]),
          rank("Green", "green", 0, [days: 120], [
            "Jumping front kick and tornado kick",
            "Partner drills (two-person set)",
            "Third form"
          ]),
          rank("Blue", "blue", 0, [days: 180], [
            "Applications of the forms",
            "Light sanda sparring",
            "First weapon (staff)"
          ]),
          rank("Brown", "brown", 0, [days: 180], [
            "Advanced form",
            "Second weapon (broadsword or spear)",
            "Chin na basics"
          ]),
          rank("Red", "red", 0, [days: 365], [
            "All forms with power and spirit",
            "Sanda sparring three rounds"
          ]),
          rank("Black", "black", 0, [days: 365], [
            "Complete syllabus and a demonstration",
            "Assists teaching"
          ])
        ]
      ),
      template(
        "wing_chun_forms",
        "Wing Chun levels",
        "kung_fu",
        "level",
        :federation,
        "Ip Man lineage form order",
        [
          rank("Siu Nim Tao", nil, 0, [], [
            "Yee jee kim yeung ma stance",
            "Centre-line theory and chain punch",
            "Siu Nim Tao form",
            "Tan pak and bong sau"
          ]),
          rank("Chum Kiu", nil, 0, [], [
            "Chum Kiu form",
            "Turning stance and stepping",
            "Dan chi sau and luk sau (poon sau)",
            "Front and side kicks"
          ]),
          rank("Biu Tze", nil, 0, [], [
            "Biu Tze form",
            "Chi sau with attacks",
            "Emergency techniques and elbows"
          ]),
          rank("Mook Yan Jong", nil, 0, [], ["Wooden dummy form (116 movements)", "Free chi sau"]),
          rank("Luk Dim Boon Kwan", nil, 0, [], ["Long pole form", "Pole drills with a partner"]),
          rank("Baat Cham Dao", nil, 0, [], [
            "Butterfly knives form",
            "Teaches the empty-hand forms"
          ])
        ]
      ),
      template(
        "capoeira_cords",
        "Capoeira cords",
        "martial_arts",
        "belt",
        :federation,
        "Brazilian Capoeira Confederation colours (groups vary)",
        [
          rank("Beginner cord", "white", 0, [], [
            "Ginga",
            "Basic esquivas (cocorinha and negativa)"
          ]),
          rank("Green", "green", 0, [days: 365], [
            "Meia-lua de frente and armada",
            "Queixada and benção",
            "Au (cartwheel) and role",
            "Sings a corrido and claps the rhythm"
          ]),
          rank("Green-yellow", "green", 0, [days: 365], [
            "Martelo and meia-lua de compasso",
            "Plays pandeiro and atabaque basics",
            "Roda game at Regional rhythm"
          ]),
          rank("Yellow", "yellow", 0, [days: 365], [
            "Rasteira and other take-downs",
            "Basic berimbau toques",
            "Angola rhythm game"
          ]),
          rank("Yellow-blue", "yellow", 0, [days: 365], [
            "Floreios (macaco and au sem mao)",
            "Leads a song in the roda"
          ]),
          rank("Blue", "blue", 0, [days: 365], [
            "Plays every instrument of the bateria",
            "History of capoeira and its masters"
          ]),
          rank("Green-yellow-blue", "blue", 0, [days: 730], [
            "Formado: teaches beginners under supervision",
            "Complete sequences of Mestre Bimba"
          ])
        ]
      ),
      template(
        "wrestling_levels",
        "Wrestling",
        "wrestling",
        "level",
        :palee,
        "No belt or grade system in Olympic wrestling (UWW)",
        [
          rank("Novice", nil, 0, [], [
            "Square and staggered stance with head up",
            "Stance motion forward · back and sideways without crossing feet",
            "Level change from stance",
            "Forward and backward rolls",
            "Front and back neck bridge (safe)",
            "Breakfall to the side and back",
            "Sprawl from stance",
            "Collar tie and inside control ties",
            "Knows scoring basics: takedown · exposure · fall",
            "Skin check and mat hygiene routine"
          ]),
          rank("Basic Skills", nil, 0, [], [
            "Penetration step (drop step) to a partner",
            "Outside step penetration",
            "Knee spin penetration",
            "Lift a partner from a level change",
            "Back step drill",
            "Back arch drill on a crash pad",
            "Hand fighting: clear ties and win inside position",
            "Snap down to front headlock",
            "Referee's position top and bottom (par terre)",
            "Hip heist from bottom"
          ]),
          rank("Takedowns", nil, 0, [], [
            "Double leg takedown with finish",
            "Single leg takedown with finish",
            "High crotch",
            "Arm drag to back or single",
            "Duck under",
            "Ankle pick",
            "Front headlock go-behind",
            "Sprawl and whizzer defence",
            "Re-attack after a failed shot",
            "Push-out awareness at the edge"
          ]),
          rank("Mat Wrestling", nil, 0, [], [
            "Gut wrench both directions",
            "Leg lace (ankle lace) turn",
            "Half nelson to pin",
            "Cradle (near side and far side)",
            "Stand-up from bottom",
            "Sit-out and turn-in",
            "Switch reversal",
            "Bridging out of a pin",
            "Defends gut wrench and leg lace from bottom",
            "Pin combination: tilt to cradle"
          ]),
          rank("Advanced", nil, 0, [], [
            "Hip toss (headlock or over-under)",
            "Arm throw",
            "Body lock and lateral drop",
            "Front body lock lift and suplex (Greco-Roman)",
            "Reverse body lock lift from par terre",
            "Underhook and 2-on-1 tie series",
            "Counter to single leg (heel lift and step over)",
            "Scramble from a stalled shot",
            "Chain wrestling: 3 linked attacks",
            "Weight management and safe cutting knowledge"
          ]),
          rank("Competitor", nil, 0, [], [
            "Full 2 × 3 minute match at competition pace",
            "Knows UWW rules: passivity · activity clock · cautions",
            "Personal A-game of 2 takedowns and 1 turn",
            "Scouts and adjusts tactics between periods",
            "Leads warm-up and drills for juniors",
            "Competes in an official tournament"
          ])
        ]
      ),
      template(
        "sambo_levels",
        "Sambo",
        "martial_arts",
        "level",
        :federation,
        "FIAS Belt System (International Sambo Federation · belt.sambo.sport): Beginner (no stripe) · Student Levels 1-6 (coloured stripes on the red/blue comp",
        [
          rank("Beginner", nil, 0, [], [
            "Breakfall forward on hands from a squat",
            "Side breakfall rolling over the shoulder from a squat",
            "Side breakfall with a rock from a squat",
            "Back breakfall with a rock from a squat",
            "Mount hold gripping arm and neck",
            "Cross-body hold with hand grips",
            "Side hold gripping arm and neck",
            "Head hold gripping arm and neck",
            "Hold from the legs embracing torso and arm",
            "Turnover with hand grips from the side",
            "Turnover with a lever",
            "Unbalance by pulling a squatting partner",
            "Unbalance by twisting or pushing a kneeling partner"
          ]),
          rank("Student Level 1", nil, 0, [], [
            "Forward fall onto a bridge rolling from a squat",
            "Forward fall on hands from standing",
            "Side fall rolling over the shoulder from standing",
            "Side and back falls with a rock from standing",
            "Mount hold with outside leg grapevine",
            "Cross-body hold gripping arm and hip",
            "Side hold gripping torso and arm",
            "Head hold embracing the torso",
            "Throw with inside shin grip",
            "Unbalancing by twisting and by pushing",
            "Back trip (podnozhka) gripping arm and belt",
            "Turnover gripping leg and arm",
            "Elbow lever through the hip from side hold",
            "Shoulder knot (uzel) from side hold"
          ]),
          rank("Student Level 2", nil, 0, [], [
            "Forward fall on arms jumping from standing",
            "Side fall rolling over partner's arm",
            "Back fall jumping forward (half flip) and backward",
            "Reverse cross-body hold gripping arm and hip",
            "Side hold gripping both arms",
            "Head hold gripping lapels under the arms kneeling",
            "Inside ankle grip throw",
            "Hip throw with a belt grip",
            "Back reaping throw gripping arm and belt",
            "Front trip gripping arm and belt",
            "Turnover by pulling or pushing the jacket wing",
            "Knee lever locking the hip with crossed legs",
            "Elbow lever after a cross-body hold",
            "Shoulder knot using the leg from side hold",
            "Escapes from mount · side · head and leg holds"
          ]),
          rank("Student Level 3", nil, 0, [], [
            "Leg-grip throw with a push",
            "Outside shin-grip throw",
            "Overhead (stomach) throw gripping neck and arm",
            "Chest throw from seated gripping arm and torso",
            "Back throw gripping the arm over the shoulder",
            "Heel trip gripping one arm with both hands",
            "Inside shin hook with a push",
            "Outside reap gripping arm and belt",
            "Turnover with belt grip and leg on the neck",
            "Turnover with inside forearm grip",
            "Reverse shoulder knot from side hold",
            "Knee lever on opponent on hands and knees",
            "Elbow lever on opponent lying on the chest",
            "Achilles lock from seated",
            "Self-defence: escapes from clothing and arm grips"
          ]),
          rank("Student Level 4", nil, 0, [], [
            "Shoulder throw (through the back) both sides",
            "Front sweep (podsechka) and side sweep in motion",
            "Double-leg pickup throw",
            "Combination: trip into hip throw",
            "Counter-throw to a hip throw",
            "Straight armlock from guard",
            "Straight knee bar from top",
            "Transitions hold to armlock in under 3 seconds",
            "Grip fighting on the sambo jacket (kurtka)",
            "Knows sport sambo scoring and banned techniques"
          ]),
          rank("Student Level 5", nil, 0, [], [
            "Sacrifice throws (sumi-style) with clean landing",
            "Pickup throws over the chest",
            "Flying armbar entry from standing",
            "Ankle lock and knee lock chains",
            "Escapes from leg locks",
            "Three-throw combinations in randori",
            "Total victory awareness (clean throw or submission)",
            "Competes in an official sambo tournament"
          ]),
          rank("Student Level 6", nil, 0, [], [
            "Personal tokui-waza: 2 signature throws on both sides",
            "Ground-to-submission chain of 3 techniques",
            "Counter-throws to 3 common attacks",
            "Tactical match plan by score and time",
            "Demonstrates and explains all student-level techniques",
            "Assists coaching beginners"
          ]),
          rank("Candidate for Master", nil, 0, [], [
            "Full FIAS student syllabus demonstrated cleanly",
            "National-level competition results",
            "Referee rules knowledge exam",
            "Teaches a full class under supervision"
          ]),
          rank("Master", nil, 0, [], [
            "International-level competition or coaching record",
            "Independent coaching of all student levels",
            "Examines and grades students"
          ])
        ]
      )
    ]
  end
end
