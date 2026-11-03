# Rank curricula research (belts, grades and levels per sport)
Date: 2026-11-03 · Decision: ADR-400 · Code: `Palee.Ranks.Domain.LadderTemplates`

This document backs the 75 rank templates that Palee offers when a box or solo coach creates a ladder («Πρότυπο»). A template is only a starting point. It is copied when a ladder is created, and the coach then edits names, colours, requirements and skills freely.

How to read it:
- **source `federation`**: the levels follow the system of a federation, examining body, school or race organiser, named in the template's `system` line. The skills are Palee's own short wording of what that level tests. They are not copied syllabus text.
- **source `palee`**: no official levels exist (or none for students), so Palee built its own from the common progressions in the sources listed.
- Palee is not affiliated with or endorsed by any body named here. Template names describe the structure ("Ballet graded levels (RAD structure)"), never the body's product.
- Minimum days or classes are set only where a source states them. Ages appear as a skill line («Ηλικία 16 ετών και άνω») because the ladder has no age field.
- Each template was fact-checked after drafting (combat and gymnastics, then dance, fitness and outdoor). The fixes are applied, and the notes below say what changed.

## 1. Naming and disciplines
"Gymnastics" in Greek boxes means very different things. The workout kinds are now split (ADR-400):

| Greek | Kind | Templates |
|---|---|---|
| Ενόργανη | `artistic_gymnastics` | Women's DP levels 1–10, Xcel, men's DP |
| Ρυθμική | `rhythmic_gymnastics` | USAG RDP levels 3–8, then FIG Junior and Senior |
| Τραμπολίνο / tumbling | `trampoline_tumbling` | BG trampoline awards 1–15, USAG tumbling 1–10 |
| Ακροβατική | `acrobatics` | Palee acro and hand-balancing levels |
| Parkour / freerunning | `parkour` | Palee parkour and freerunning levels |
| Γυμναστική (CrossFit style) | `gymnastics` (kept) | CrossFit gymnastics skills, generic levels 1–10 |
| Calisthenics / freestyle | `calisthenics` | Palee calisthenics, street workout freestyle |

"Freestyle" was read as street-workout freestyle (bar statics and dynamics). It could also mean freestyle swimming, freestyle dance (ISTD Disco Freestyle) or freestyle skiing/BMX. This is an open question for the product owner.

New kinds: combat `judo karate taekwondo kung_fu krav_maga`; dance `ballet contemporary_dance latin_dance street_dance`; outdoor `skateboarding`. Salsa, bachata and kizomba belong to `latin_dance`. Hip-hop, R&B/commercial, breaking, reggaeton and heels belong to `street_dance` (reggaeton could also be `latin_dance`; open question).

## 2. Combat sports
| Template | Source | System and evidence |
|---|---|---|
| bjj_adult | federation | IBJJF graduation system: white, blue (16+), purple, brown (18+), black. Minimum time is 2 years at blue, 18 months at purple and 1 year at brown. The old Palee ladder had these shifted by one belt; fixed. https://ibjjf.com/graduation-system · https://en.wikipedia.org/wiki/Brazilian_jiu-jitsu_ranking_system |
| bjj_kids | federation | IBJJF kids belts (grey, yellow, orange, green, with white and black variants) for ages 4–15. Only kids-legal techniques are listed (the IBJJF forbidden-techniques table). https://ibjjf.com/rails/active_storage/blobs/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaHBBcE1WIiwiZXhwIjpudWxsLCJwdXIiOiJibG9iX2lkIn19--e13c15f6e568323ecea8ef21a102b726067a4540/20240101_GolpesProibidos_EN.pdf |
| karate_kyu | palee | The original 7-belt ladder. No single federation uses it, so it is now marked `palee`. |
| karate_shotokan_kyu | federation | Shotokan kyu with the shoto.uk colours and intervals. Colours vary by association. https://shoto.uk/information/syllabus-kyu-grades/ · https://www.englishshotokan.net/syllabus/kyu-grades |
| karate_kyokushin_kyu | federation | Kyokushin colours. The IKO allows at most four gradings a year, so each grade is set to 90 days. https://en.wikipedia.org/wiki/Kyokushin |
| judo_kyu | federation | Common European kyu colours. Intervals follow British Judo (30 days for the low kyu, 90 days for the higher ones). https://britishjudo.org.uk/wp-content/uploads/2025/02/Kyu-Syllabus-January-2025.pdf · https://en.wikipedia.org/wiki/Rank_in_judo |
| taekwondo_geup | federation | Kukkiwon 10th geup to 1st dan or poom. British Taekwondo sets 90 days per geup and 180 days before dan. https://www.britishtaekwondo.org.uk/martial-art-gradings/ · https://www.britishtaekwondo.org.uk/wp-content/uploads/2026/02/National-Dan-Grading-Entry-Pack-2026.pdf · https://www.kukkiwon.or.kr/ |
| aikido_kyu | federation | Aikikai Hombu practice days per kyu. There is no 6th kyu at Hombu; it is a dojo "Beginner" level. Shodan from age 15. https://aikikai.or.jp/eng/hombudojo/grading/ |
| muay_thai_khan | federation | Kru Muay Thai Association khan 1–10. No day minimums. Khan 10 is the instructor level. Armband colours vary by gym. https://krumuaythai.or.th/become-member/structure · https://krumuaythai.or.th/courses/student · https://lincolnthaiboxing.co.uk/?p=1343 |
| kickboxing_wako | federation | WAKO optional grading programme (2025). Blue and brown need 180 days. https://wako.sport/_files/ugd/6445bf_cae3b433b30e4526b97928d02379485f.pdf |
| boxing_awards | federation | Modelled on the England Boxing award structure (three non-contact and three contact awards). https://www.englandboxing.org/ |
| mma_levels | palee | MMA has no rank system. Levels combine BJJ, wrestling and striking basics. |
| krav_maga_grades | federation | IKMF/KMG patches: Practitioner 1–5, Graduate 1–5, Expert. Detailed per-patch content is partly unverified. https://kravmaga-ikmf.com/sections/civilian/ |
| krav_maga_belts | federation | FEKM colour belts, at most one belt a year (365 days each). https://fekm-uk.com/belts-and-grades/ |
| kung_fu_sash | palee | Sash colours and syllabi differ by style and school. A generic ladder, now marked `palee`. |
| wing_chun_forms | federation | Ip Man lineage form order: Siu Nim Tao, Chum Kiu, Biu Tze, Mook Yan Jong, Luk Dim Boon Kwan, Baat Cham Dao. |
| capoeira_cords | federation | Confederação Brasileira de Capoeira student cords in CBC order (green, yellow, blue, then the combinations). Groups vary widely. https://pt.wikipedia.org/wiki/Capoeira · https://www.frederick.ac.cy/fu_documents/cips/5673.pdf |
| wrestling_levels | palee | UWW has no grade system. Palee levels run from stance to competition. |
| sambo_levels | federation | FIAS belt system: Beginner, Student levels 1–6, Candidate, Master, Grandmaster. Student L4 to Master content is a Palee extension. https://belt.sambo.sport/ |

The fact-check changed the bjj_kids illegal moves, Shotokan colours and intervals, Kyokushin intervals, judo intervals, the aikido 6th kyu, Muay Thai days, WAKO intervals and skills, FEKM intervals, capoeira order and Greek cord names, taekwondo intervals, and the karate_kyu and kung_fu_sash sources.

## 3. Gymnastics, acrobatics, calisthenics, parkour
| Template | Source | System and evidence |
|---|---|---|
| gymnastics_levels | palee | The original generic levels 1–10, with no skills. |
| artistic_women_levels | federation | USA Gymnastics Development Program levels 1–10. The fact-check moved the DP skills one level earlier: kip and RO-BHS at L4, back tuck and flyaway at L5. https://gymnasticshq.com/level-4-gymnastics-requirements · https://gymnasticshq.com/level-5-gymnastics-requirements |
| artistic_women_xcel | federation | Xcel Bronze, Silver, Gold, Platinum, Diamond, Sapphire. Platinum and Diamond bars are written as "special requirements" rather than fixed skills. https://gymnasticshq.com/gymnastics-levels/ |
| artistic_men_levels | federation | USA Gymnastics men's DP, six apparatus. Greek apparatus names are «Ασύμμετροι ζυγοί» (women), «Δίζυγο» and «Μονόζυγο» (men). |
| rhythmic_levels | federation | USAG Rhythmic Development Program levels 3–8 (L3 floor plus one apparatus, L4 group floor plus two, L5–L8 floor plus three) and then FIG Junior (13+) and Senior (16+). https://static.usagym.org/PDFs/Rhythmic/Rules/rp/3_competitionstructure.pdf |
| trampoline_awards | federation | British Gymnastics proficiency awards 1–15. The first somersaults come at Award 10 and the barani at 12, with no doubles. Award 15 has the ball-out barani, full twist, rudi and cody (tariff 5.6). https://brentwoodtc.org/bg_award_levels.htm |
| tumbling_levels | federation | USAG tumbling levels 1–10 (2025–2029 routines): RO-BHS rebound at L3, the back tuck at L5, the first whip at L6, the 360 twist at L8, back full at L9 and the double at L10. https://static.usagym.org/PDFs/T&T/Rules/devcop/routines_tu25.pdf |
| acrobatics_levels | palee | Acro pairs and hand balancing as taught by circus schools. |
| crossfit_gymnastics | palee | Kipping, strict and ring progressions from CrossFit gymnastics courses. |
| calisthenics_levels, street_workout_freestyle | palee | Street-workout strength and freestyle bar progressions (front lever, planche, muscle-up; then dynamics and power moves). |
| parkour_levels, freerunning_levels | palee | Technique tiers used by parkour schools (precision, vaults, climb-ups; then flips). Parkour UK and ADAPT certify coaches, not students. |

## 4. Dance, pole and aerial
| Template | Source | System and evidence |
|---|---|---|
| ballet_rad_graded | federation | RAD graded structure: Pre-Primary, Primary, Grades 1–8. https://www.royalacademyofdance.org/ |
| ballet_rad_vocational | federation | RAD vocational order: Intermediate Foundation, Intermediate, Advanced Foundation, Advanced 1, Advanced 2, Solo Seal. Exam names keep their English name with a gloss in every language (msgctxt "exam"). |
| ballet_cecchetti, tap_grades, jazz_grades | federation | ISTD Cecchetti, Tap and Modern Theatre ladders; see Appendix A. https://www.istd.org/examinations/examinations-structure/ · https://www.istd.org/dance/dance-genres/tap/tap-examinations-and-qualifications/ |
| ballet_vaganova | federation | Vaganova Academy 8-year programme. The year-by-year content is reconstructed (±1 year), see Appendix A. |
| contemporary_grades | palee | **Changed by the fact-check.** The ISTD has no graded contemporary exams; ISTD Contemporary is vocational only. The graded contemporary body is Rambert Grades (Grades 1–8). The template is now Palee's own 6 grades. Switching to the Rambert 8-grade structure is an alternative. https://istd.org/documents/contemporary-dance-syllabus-outline-june-2021 · https://www.rambertgrades.com/syllabi-exams/grades-1-8/ |
| latin_medals | federation | ISTD/IDTA style medal tests: Social, Bronze, Silver, Gold, Gold Star. The dance count per medal is not published, so the skills say "in the chosen dances". https://istd.org/dance/dance-genres/latin-american/latin-american-exams-and-qualifications |
| hiphop_levels | federation | ISTD Street Dance Medal Series Bronze, Silver and Gold (spec S450), plus a Palee starter level. https://www.istd.org/documents/street-dance-medal-tests-specification |
| salsa, bachata, kizomba, commercial_rnb, breaking, reggaeton, heels | palee | No examining body grades these. Levels follow common school progressions. The breaking skills cover the WDSF element families (toprock, footwork, power, freezes). |
| dance_fitness_levels | palee | Zumba licenses instructors only; member levels are Palee's. |
| pole_levels, aerial_silks_levels, aerial_hoop_levels, aerial_yoga_levels | palee | Common studio and circus-school progressions (fireman spin → invert → aerial invert; star drop before double star). |

Greek wording fixed by the fact-check: «Improver» is «Επίπεδο βελτίωσης» (kizomba «Αρχάριοι+»), «Starter» is «Εισαγωγικό», and the French terms stay in Latin script («Enchaînements σε πουέντ»).

## 5. Fitness, strength, endurance, swimming, yoga
| Template | Source | System and evidence |
|---|---|---|
| crossfit_levels | palee | CrossFit has no athlete levels. Scaled → Rx → Rx+ uses the published scaling and the benchmark workouts. |
| metcon_levels | palee | Conditioning benchmarks (rowing, running, burpees) for class formats. |
| hyrox_divisions | federation (organiser's system) | HYROX race divisions: Open, Pro, Doubles, Relay, Elite 15. The stations follow the 2025/26 rulebook (100 wall balls). Elite 15 places come from Majors and regional championships. https://hyroxdach.com/wp-content/uploads/2025/06/25_26-Singles-Rulebook_en_R1.pdf · https://morningchalkup.com/2025/03/27/new-hyrox-qualification-rule/ |
| weightlifting_classes | federation | The Russian/EVSK sports classification (national tables, not the IWF): Class III, II, I, CMS, MS and MSIC. |
| powerlifting_levels | palee | Bodyweight-multiple strength standards. |
| swim_stages | federation | Swim England Learn to Swim stages 1–7. Stages 4–7 were rebuilt from the official outcomes: tread water at 5, 25 m of one stroke at 6, and four strokes, 100 m and the sitting dive at 7. https://uk.gomotionapp.com/hbsc/UserFiles/File/documents/learn-to-swim-stage-1-7-awards_034464.pdf |
| yoga_ashtanga | federation (school's system) | Mysore order: sun salutations → standing → Primary → Intermediate → Advanced A. |
| kettlebell_sport_ranks | federation | Rank 3, 2, 1, CMS, MS, MSIC (IUKL/IKO). The professional bell is from CMS. https://kettlebellworld.org/ranking-tables |
| kettlebell_hardstyle | palee | Built from StrongFirst standards (SFG I, Simple & Sinister). https://www.strongfirst.com/certifications/sfg-i-requirements/ |
| strongman, running, road_cycling, indoor_cycling, rowing, pilates_mat, pilates_reformer, mobility, hiit, strength | palee | See Appendix B for sources and source notes. |

## 6. Outdoor: skateboarding and climbing
| Template | Source | System and evidence |
|---|---|---|
| skateboarding_levels | palee | Built from Skateboard GB beginner awards and the common progression: push → kickturn → drop-in and ollie → 50-50 → kickflip → rail. https://skateboardgb.org/ |
| climbing_nicas | federation | NICAS Level 1 New Climber, 2 Foundation, 3 Technical, 4 Lead, 5 Advanced. Unsourced grade thresholds were removed. https://www.nicas.co.uk/brand_central/nicas-climbing-scheme-overview/ |
| bouldering_grades | palee | One level per V-grade, with the usual Font equivalent in brackets. Strictly, V3 is 6A/6A+, V4 6B/6B+, V5 6C/6C+ and V8 7B/7B+. The V-scale is a convention, not a federation. |

## 7. Uncertainties and open questions
- Skills are translated into Greek only. The other ten languages get template names, `system` lines and shared rank names, and their skills fall back to English.
- Krav Maga per-patch content, the Vaganova year content, the kettlebell bell per rank and the Muay Thai armband colours vary by school or are unverified.
- Federations revise syllabi (for example the ISTD Tap Advanced 1 from October 2026). Templates are copied once, so a box keeps its own version.
- Alternatives a box may prefer: IDTA or BATD for dance, Cecchetti Council of America, Rambert Grades for contemporary, the ISTD Tap Awards, and other karate associations' colours.

## Appendix A: dance and grappling research notes (helper)

### Rank templates: dance and grappling (reduced scope)

Scope, as the coordinator narrowed it: jazz, tap, Vaganova ballet, Cecchetti ballet, kizomba, zumba/dance fitness, aerial hammock/yoga, wrestling, sambo. The data is in `dance-acro.json`: 9 templates, 72 levels and 766 skills. Every template has `style: "level"`. Colors are null and `max_stripes` is 0. No skill text contains a comma; "·" is used instead. `min_days` and `min_classes` are null everywhere, because the sources give minimum **ages**, not days or class counts. The ages are listed below.

#### Tap: ISTD (federation)
- Ladder: Pre-Primary → Primary → Grades 1–6 (Ofqual regulated) → Intermediate → Advanced 1 → Advanced 2. Each grade's step vocabulary was taken directly from the ISTD Tap syllabus outline (April 2023), for example: G1 shuffle/flap/pick-up step; G2 4-beat cramp roll and single time step; G3 5-beat riff, waltz steps and double time step; G4 ripples, pull back and triple time steps; G5 wing preparations, Maxi Ford and Shim Sham; G6 criss-cross/progressive shuffles and scuffles; Intermediate Suzie Q, cahito and drum cramp roll; Adv 1 roll time steps; Adv 2 rattles and Eddie's riff.
- Minimum ages: Pre-Primary/Primary 5, Grade 1 6, Intermediate 13 (recommended). Passing Intermediate is required before Advanced 1, and Advanced 1 before Advanced 2.
- Uncertainty: the Advanced 1 syllabus was revised from 1 Oct 2026, and the content here is the 2023 version. ISTD's tap vocational list has no Intermediate Foundation.
- Alternatives: IDTA Tap, BATD Tap, and the ISTD Tap Awards and Adult Popular Tap Levels 1–6.
- Sources: https://www.istd.org/documents/tap-syllabus-outline-april-2023/1tap-syllabus-outline-april-2023.pdf · https://www.istd.org/dance/dance-genres/tap/tap-examinations-and-qualifications/

#### Jazz: ISTD Modern Theatre (federation)
- ISTD Modern Theatre is the UK examined jazz/theatre-jazz genre. Its description of the genre includes "isolations, travelling steps, high kicks, leaps and turns".
- Ladder: Primary → Grades 1–6 → Intermediate Foundation → Intermediate → Advanced 1 → Advanced 2. Source: Modern Theatre Specification S01000 v1.1 (July 2026). The Grade 5 and 6, Intermediate Foundation, Intermediate, Advanced 1 and Advanced 2 vocabulary lists were taken verbatim, for example drag runs, accented hop, tilts, drag/twist/swivel turns, barrel turns and stag leap. Grades 1–3 come from the exercise headings plus the "step vocabulary for teacher's use" list (G3: triple runs, jazz pas de bourrée, split jump, flick kicks).
- Minimum ages: Primary 5, Grade 1 6, Intermediate Foundation and Intermediate 13 (recommended).
- Uncertainty: the Grade 2 skills are partly inferred from the exercise structure, because the PDF layout is in columns.
- Alternatives: IDTA Jazz grades, BATD Jazz, ISTD Modern Theatre Jazz Awards (Bronze/Silver/Gold), and US college jazz proficiency levels (UGA beginner/intermediate/advanced, https://www.dance.uga.edu/sites/default/files/Jazz%20Dance%20Proficiency%20Standards.pdf).
- Sources: https://www.istd.org/documents/modern-theatre-primary-class-examinations-jazz-awards-grades/istd-modern-theatre-specification-s01000-v1.1-july-2026.pdf · https://istd.org/examinations/theatre-dance-syllabus-outlines

#### Ballet: Cecchetti (federation)
- ISTD Cecchetti Classical Ballet ladder: Pre-Primary → Primary → Grades 1–6 → Intermediate Foundation → Intermediate → Advanced 1 → Advanced 2, then the Enrico Cecchetti Diploma, which is omitted as a professional level. A parallel class-exam track exists (Standards 1–6 and Senior Certificates 1–2). The barre, centre, pirouette and allegro content of each level was taken from the July 2024 syllabus outline. Option 1 is pointe and Option 2 is the boys/elevation path.
- Minimum ages: Pre-Primary/Primary 5, G1–2 7, G3 8, G4 9, G5 10, G6 11, Int Foundation 11, Intermediate 12, Adv 1 13, Adv 2 14.
- Alternatives: Cecchetti Council of America (Grades 1–7 and Pre-Professional) and Cecchetti Ballet Australia.
- Sources: https://istd.org/documents/cecchetti-classical-ballet-syllabus-outline-july-2024/syllabus-outline-cecchetti-classical-ballet-july-2024.pdf · https://www.istd.org/documents/cecchetti-grades-vocational-class-examinations-and-cecchetti/istd-cecchetti-specification-v2.0.pdf · https://www.cecchetti.org/students/syllabus-overview/

#### Ballet: Vaganova (marked federation, with an uncertainty flag)
- Structure: the 8-year Vaganova Academy programme. Kostrovitskaya's *100 Lessons in Classical Ballet* is "the eight-year program of Leningrad's Vaganova Choreographic School". The Classical Dance Alliance compresses it into 6 years.
- **Main uncertainty:** I found no open official year-by-year list. I reconstructed the year content from the standard Kostrovitskaya/Vaganova progression. Year 1 covers barre facing the wall, basic sautés and early pointe relevés. Year 2 adds rond en l'air, petit battement, small poses, arabesques, assemblé and sissonne. Year 3 brings pirouettes from 5th/2nd, entrechats and pas de basque. Year 4: pirouettes from 4th, doubles, cabriole 45°, brisé. Year 5: tours in big poses, jeté entrelacé, saut de basque, entrechat six. Year 6: renversé, fouettés 8–16, grand fouetté en tournant. Year 7: 32 fouettés, entrechat huit, pas de deux. Year 8: graduation and repertoire. Where a step falls varies by ±1 year between schools. A ballet specialist should review this.
- Sources: https://www.goodreads.com/book/show/9145.100_Lessons_in_Classical_Ballet · https://classicaldancealliance.org/six-year-syllabus-overview · https://learnballetonline.teachable.com/p/vaganovaballetlevelone · https://accademialascala.it/systemFiles/htmleditor/upload_dir/triennio-danza/programs-i-2024.pdf

#### Kizomba (palee)
- No examining body grades kizomba. School course outlines (beginner/intermediate/advanced) share a core vocabulary: basic step, saídas (including saída da dama), retrocesso, vírgula, 3x3, balance, pivots, around the world and foot swipe. One studio lists these as its intermediate prerequisites. One school argues there is "no fixed basic step". I designed 5 Palee levels: Foundations → Improver → Intermediate → Advanced (kota, tarraxinha, urban kiz) → Master.
- Sources: https://iknowhow.teachable.com/p/kizomba-beginners-intermediate-advanced · https://snowmotion.punchpass.com/classes/18549416 · https://ycvdance.punchpass.com/series/26074

#### Zumba / dance fitness (palee)
- Zumba runs only instructor licensing. Basic 1 teaches the four core rhythms (merengue, salsa, cumbia, reggaeton) and the "Zumba formula" for reading the sections of a song. Basic step descriptions came from third-party guides. I designed 5 member levels: Starter → Core Rhythms → World Rhythms → High Energy → Leader.
- Sources: https://www.zumba.com/en-US/training/2026-10-14_B1_Maipu_CL_Rodrigo_Diaz · https://nas.com/zumba/events/zumba-basic-1 · https://livestrong.com/article/259945-basic-zumba-moves

#### Aerial hammock / aerial yoga (palee)
- There is no student grading body; AYOGA, Unnata and AntiGravity train teachers only. Studio levels are consistent with each other. Level 1 covers postures, thigh lock, the diaper wrap and basic inverts (gazelle, butterfly, Buddha). Moving to Level 2 means doing straddle and diamond several times. Level 2/3 approval needs a pullover to front balance/swan 3–5 times, the bomb drop and the waterfall. A higher class needs the hip key and cross-back entries. I designed 5 levels: Intro, L1–L4.
- Sources: https://serpentinestudios.punchpass.com/classes/17018319 · https://aerialrevolution.pike13.com/e/285586701 · https://wildheart-aerial-school.teachable.com/courses/768872 · https://everosestudios.offeringtree.com/offerings/aerial-yoga-level-1-2-pearl?embed=true

#### Wrestling (palee)
- UWW has no belts or grades. USA Wrestling's Copper/Bronze/Silver/Gold levels are coach certifications. Wrestling Canada's Bronze/Silver/Gold skill-award page now returns 404. I built the Palee levels on USA Wrestling's "seven basic skills": stance, motion, level change, penetration, lifting, back step and back arch. Penetration variants are the drop step, the outside step and the knee spin. After those come takedowns, par terre (gut wrench, leg lace), Greco-Roman throws and competition skills. 6 levels: Novice → Basic Skills → Takedowns → Mat Wrestling → Advanced → Competitor.
- Sources: https://content.usawmembership.com/articles/2175 · https://en.wikipedia.org/wiki/Collegiate_wrestling_moves · https://archive.teamusa.com/usa-wrestling/coaches/ncep-certification.html · https://fivepointmove.com/?p=18960

#### Sambo: FIAS Belt System (federation, partly palee)
- FIAS levels: Beginner (no stripe) → Student Levels 1–6 (coloured stripes on the red/blue belt) → Candidate for Master → Master → Grand Master. FIAS says only that stripes run "from white to burgundy" or "white to purple (Master)". **The colour for each level is not published, so colours are null.**
- The techniques for Beginner and Student Levels 1–3 were taken from belt.sambo.sport lesson pages: breakfalls, hold-downs, turnovers, unbalancing, podnozhka, hip and inside-ankle throws, elbow/knee levers, shoulder knots, the Achilles lock and escapes.
- **Student Levels 4–6, Candidate for Master and Master are a Palee extension.** FIAS has not published them openly. Grand Master is omitted as honorary.
- Alternative: Russian sports ranks (youth ranks → 3rd–1st adult → CMS → Master of Sport).
- Sources: https://belt.sambo.sport/ · https://belt.sambo.sport/lessons/junior · https://belt.sambo.sport/lessons/1st_rank · https://belt.sambo.sport/lessons/2_rank · https://belt.sambo.sport/lessons/3_rank · https://sambo.sport/en/news/fias-zapustila-ofitsialnyy-sayt-poyasnoy-sistemy/

#### Greek terminology notes
- In ballet, jazz and tap, French and English step names stay in Latin script (demi-plié, shuffle, flap), the way Greek dance schools use them. Exam level names keep the English label with a Greek gloss, for example «Grade 1 (βαθμίδα 1)».
- Wrestling uses «Πάλη (ελευθέρα και ελληνορωμαϊκή)» and «παρτέρ». Sambo uses «Σάμπο», with Russian terms (podnozhka, uzel) kept in brackets.

#### Scope dropped
The originally assigned sports were drafted by the main rank agent: artistic, rhythmic, trampoline, tumbling, acro, calisthenics, parkour, silks, lyra, pole, RAD ballet, contemporary, hip-hop, breaking, heels, Latin, salsa, bachata, skateboarding and climbing. They are not included here.

## Appendix B: fitness and endurance research notes (helper)

### Fitness and endurance rank templates: research notes

Scope (revised by coordinator): strongman, kettlebell (hardstyle and girevoy sport), running, road and indoor cycling, rowing, Pilates (mat and reformer), mobility/flexibility, HIIT/bootcamp, general strength training. CrossFit, metcon, Hyrox, weightlifting, powerlifting, swimming and yoga were dropped because the main agent already drafted them.

Output: `fitness-endurance.json` has 12 templates, 69 levels and 476 skills (EN and EL). All templates use `style: "level"`, `color: null` and `max_stripes: 0`. No skill text contains a comma. Numbers are written with "·", "x" or a decimal point.

#### Summary

| key | system | levels | skills | workout type |
|---|---|---|---|---|
| strongman_palee | palee | 6 | 54 | strongman |
| kettlebell_hardstyle | palee (built on StrongFirst standards) | 7 | 47 | kettlebell |
| kettlebell_sport_ranks | federation (IUKL/IKO ranks) | 6 | 28 | kettlebell |
| running_palee | palee (NHS C25K + Higdon) | 7 | 43 | running |
| road_cycling_palee | palee (first 3 levels follow Bikeability) | 6 | 36 | cycling |
| indoor_cycling_palee | palee | 5 | 27 | indoor_cycling |
| indoor_rowing_palee | palee (British Rowing / Concept2 technique) | 6 | 35 | rowing |
| pilates_mat_classical | palee (classical Basic/Int/Adv order) | 5 | 50 | pilates |
| pilates_reformer_classical | palee (classical reformer order, Palee grouping) | 5 | 48 | pilates |
| mobility_flexibility_palee | palee (FRC + split/bridge progressions) | 6 | 39 | mobility |
| hiit_bootcamp_palee | palee (ACE interval guidance) | 5 | 35 | hiit |
| strength_training_palee | palee (Rippetoe stages + Dan John standards) | 5 | 34 | strength |

No new `discipline_workout_type` keys are needed. `min_days` and `min_classes` are null everywhere because no source sets a minimum time in grade.

#### Strongman
- No federation runs an athlete level ladder. Contests are split by bodyweight class and by novice, open or pro division. The event categories come from [Fitnessvolt events](https://fitnessvolt.com/strongman/events/): deadlift, overhead (log, axle, Viking, circus DB), squat, stones, farmers, yoke, carries, throws, flips, grip, loading, vehicle pull and medley.
- The only sourced novice loads come from one UK novice contest, under 95 kg class ([Sugden Barbell / Krunchmania](https://www.sugdenbarbell.co.uk/competitions/KRUNCHMANIA-Novice-Strongman-Competition-(under-95kg-and-over-95kg)-402)): farmers 100 kg x 25 m in 60 s, log 70 kg for max reps in 75 s, yoke 200 kg x 25 m in 60 s. These are included as reference loads only.
- [Fitnessvolt standards](https://fitnessvolt.com/strongman/strength-standards/) has tiered tables (beginner to elite) but their numbers were not readable. Its pro benchmarks use local, national, world class and elite tiers.
- Levels: Foundations, Implement Novice, Novice Competitor, Intermediate, Advanced, Open Competitor.

#### Kettlebell: hardstyle (palee)
- The [StrongFirst SFG I requirements](https://www.strongfirst.com/certifications/sfg-i-requirements/) list six skills: swing 10 per side, double clean 5, press 5 per side, double front squat 5, snatch 5 per side, get-up 1 per side. The snatch test is 100 reps in 5 min. Bell sizes: women 12 kg up to 59 kg bodyweight, otherwise 16 kg. Men 20 kg up to 68 kg, 24 kg up to 100 kg, 28 kg above. Masters (50 to 64) use 12 kg for women and 20 kg for men. Seniors (65+) do 50 reps in 3 min.
- Simple & Sinister ([StrongFirst](https://www.strongfirst.com/sinister/), [LiftVault](https://liftvault.com/programs/strength/simple-sinister-kettlebell-program-spreadsheet-pavel/)): 100 one-arm swings in 5 min, then 10 get-ups in 10 min. Simple is 32/32 kg for men and 24 kg swing / 16 kg get-up for women. Sinister is 48/48 kg for men and 32 kg swing / 24 kg get-up for women. LiftVault is a secondary summary of the book.
- Levels: Foundations, Swing and Get-up, Clean and Press, Snatch, Simple Standard, SFG Standard, Sinister. The reps in the first four levels are Palee coaching defaults.

#### Kettlebell sport / girevoy sport (federation)
- Ranks from lowest to highest are Rank 3, Rank 2, Rank 1, CMS, MS and MSIC ([Kettlebell World / IKO](https://kettlebellworld.org/ranking-tables)). IKMF separately awards HMS, MSWC, MS and CMS for marathon formats ([IKMF](https://ikmf-world.com/rules/ranks-and-rules)). You earn a rank by reaching a rep total in a 10-min set (some tables also have 5 min), set per sex, bodyweight class and bell. The thresholds are only in the IKO 2024 table PDF and images and are not reproduced.
- IUKL competition bell weights, from the [FFForce 2025 rulebook](https://www.ffforce.fr/medias/fichiers/Saison%202025/KETTLEBELL/Arbitrage/2025_00_R%C3%A8glement%20sportif%20international%20et%20national.pdf):

  | Category | Men | Women | Notes |
  |---|---|---|---|
  | Amateur seniors (B) | 24 kg | 16 kg | |
  | Professional seniors (A) | 32 kg | 24 kg | Heavier for jerk and long cycle: men 40 kg, women 32 kg |
  | U-18 | 24 kg (boys) | 16 kg (girls) | |
  | U-16 | 16 kg (boys) | 12 kg (girls) | |

- Events ([Wikipedia](https://en.wikipedia.org/wiki/Kettlebell_lifting)): jerk, long cycle, snatch (one hand switch) and biathlon (jerk then snatch). Sets are usually 10 min.
- Uncertainty: I tied Rank 1 to amateur bells and MS/MSIC to professional bells as a training convention. Check the IKO tables to see which bell each rank actually requires.

#### Running (palee)
- [NHS Couch to 5K](https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan/) takes 9 weeks with 3 runs a week, each with a 5-min walk warm-up and cool-down.
  - Week 1: run 1 min, walk 1.5 min, repeated.
  - Week 5, run 3: 20 min continuous.
  - Week 9: 30 min continuous, all three runs.
- Hal Higdon Novice 1 plans ([TrainingPeaks](https://www.trainingpeaks.com/training-plans/running/marathon/tp-139218/hal-higdon-marathon-novice-1), [Running with Rock](https://runningwithrock.com/hal-higdon-marathon-training-plan/)):
  - Half marathon: 12 weeks.
  - Marathon: 18 weeks, long runs from 6 to 20 miles, 4 run days plus cross-training.
  - The 10-mile peak long run in the half plan is inferred, not confirmed.
- England Athletics levels are for leaders and coaches, not runners.
- Levels: Walk-Run Starter, First 5K, 5K Improver, 10K, Half Marathon, Marathon, Performance Runner. No pace standards were invented.

#### Road cycling (palee)
- The first three levels mirror the UK [National Standard for Cycle Training](https://assets.publishing.service.gov.uk/media/5faaa059e90e073062910954/national-standard-cycling-document.pdf) / Bikeability ([delivery guide](https://professionals.bikeability.org.uk/download/704), [Cycling UK](https://www.cyclinguk.org/article/what-bikeability)):
  - L1 covers Roles 1 and 2 away from traffic.
  - L2 covers Roles 1 to 4 on simple roads.
  - L3 covers Roles 1 to 4 on complex roads.
- British Cycling Go-Ride has no single national award ladder; clubs run their own Bronze, Silver and Gold schemes ([example](https://www.ppycc.org.uk/?p=10763)).
- The 100 km "metric century" and the 20-min FTP test are widely used standards, not sourced federation rules.

#### Indoor cycling (palee)
- Spinning, Schwinn and Stages certify instructors, not riders. The movements are seated flat, seated and standing climbs, jumps and sprints.
- Cadence: flats and jumps about 80 to 110 rpm, climbs about 60 to 80 rpm ([Wikipedia](https://en.wikipedia.org/wiki/Indoor_cycling)). Spinning bases its cadences on outdoor riding ([spinning.com](https://spinning.com/understanding-cadence-indoors-and-out/)). The 60 to 110 rpm range is an envelope, not a safety rule.

#### Rowing (palee)
- Technique areas come from [British Rowing Go Row Indoor](https://www.britishrowing.org/indoor-rowing/go-row-indoor/how-to-indoor-row/british-rowing-technique/): posture, grip, recovery, catch, drive, finish. The drive goes legs, body, arms, and the recovery reverses it. Recovery takes about twice as long as the drive.
- Drills come from [Concept2](https://www.concept2.com/indoor-rowers/training/technique-videos/rowing-drills): arms and body, pauses, counting rhythm (drive on 1, recovery on 2-3-4) and legs only. The pick drill is from [CrossFit](https://crossfit.com/essentials/rowing-the-pick-drill).
- The 2k, 5k and 30-min tests and the [Concept2 rankings](https://log.concept2.com/rankings/2022/rower/2000) are standard benchmarks; no times were invented.
- I added a "Water Transition" level (capsize test, squaring and feathering, launching) from general learn-to-row practice. I found no British Rowing staged learn-to-row award.

#### Pilates mat (palee)
- Exercises and reps come from the [Pilatesology classical order sheets](https://pilatesology.com/wp-content/uploads/2024/04/Classical-Mat-Exercises-Basic-Intermediate-Advanced-With-LINKS.pdf) (text extracted from the PDF):
  - Basic has 7 exercises: Hundred 100, Roll Up 3-5, Leg Circles 3-5, Rolling Like a Ball 5-10, Single Leg Stretch 5-10, Double Leg Stretch 5-10, Spine Stretch 3-5.
  - Intermediate has 22 exercises, adding the straight-leg stretches, Criss Cross, Open Leg Rocker 6, Corkscrew, Saw, Neck Roll, the kicks, Neck Pull 5, the side-kick series, Teaser 1 and Seal 6.
  - Advanced is the full order up to Push Ups.
- The base is Joseph Pilates' 34 exercises in *Return to Life* ([Online Pilates Classes](https://onlinepilatesclasses.com/blog/the-original-34-classical-pilates-mat-exercises), [Pilates Anytime](https://www.pilatesanytime.com/blog/legacy/understanding-return-to-life)).
- I split the Advanced order into "Advanced Order" and "Master Repertoire" to stay under 20 skills per level. The Fundamentals level (pre-Pilates) is Palee-designed.

#### Pilates reformer (palee)
- The full classical order has 46 items, from Footwork to Russian Squat ([Online Pilates Classes](https://onlinepilatesclasses.com/blog/full-pilates-reformer-order-and-tutorial/)).
- The source gives no levels, so the Basic, Intermediate, Advanced and Master grouping is Palee's own. Pilatesology publishes separate reformer orders by level ([link](https://pilatesology.com/?p=233603)), but I could not read them; use them to refine the grouping. The [BASI Block System](https://www.basipilates.com/innovation/basi-block-system/) is an alternative structure.

#### Mobility and flexibility (palee)
- From FRC: daily CARs, PAILs and RAILs done as a pair, then end-range strength ([Prehab Guys](https://theprehabguys.com/intro-to-frc/), [Substack](https://anaritaalmeida.substack.com/p/understanding-frc-and-how-it-is-a)).
- Front split progression goes from block to cushion to floor ([GymnasticsHQ](https://gymnasticshq.com/how-to-do-a-split/), [Kangaroo Hoppers](https://www.kangaroohoppers.com/blogs/news/how-to-do-the-splits)).
- The bridge progression (glute bridge, table-top, head-on-floor, full bridge, walk-down, stand-up) is from common gymnastics and calisthenics practice. I did not find an authoritative source for it.
- Hold times are Palee defaults.

#### HIIT and bootcamp (palee)
- [ACE](https://www.acefitness.org/education-and-resources/professional/expert-articles/5880/a-basic-high-intensity-interval-training-routine-for-beginning-exercisers): beginners start at 30:15 work to rest, at RPE 4 to 6. Other guides suggest progressing by adding 5 to 10 s of work or cutting 10 to 15 s of rest ([WeightLossResources](https://www.weightlossresources.co.uk/exercise/plans/beginners-hiit-workouts.htm)).
- Tabata (20:10 x8) is widely standard but too hard for true beginners. I found no ACSM citation.
- Rep and time targets are Palee defaults. The template can also be used for bootcamp and circuit_training.

#### Strength training (palee)
- Rippetoe's stages ([Practical Programming](https://www.goodreads.com/book/show/20765602-practical-programming-for-strength-training), [Fitnessvolt LP summary](https://fitnessvolt.com/starting-strength-lp/)):
  - Novice adds load every session.
  - Advanced novice adds a light squat day.
  - Intermediate progresses weekly.
  - Advanced progresses over longer blocks.
- Dan John's "expected" and "game changer" standards come from secondhand copies ([StrongFirst forum](https://www.strongfirst.com/community/threads/dan-johns-strength-standards.2313/), [Substack](https://savagezen.substack.com/p/strength-and-conditioning-standards-for-athletes)) and versions differ. The template uses them as reference only: deadlift 1.5x and 2x bodyweight, 15 pull-ups, bodyweight squat x15.

#### Notable uncertainties
1. The kettlebell sport rank rep thresholds are not included, and the bell each rank requires is unconfirmed. They need the IKO 2024 tables, which are only published as PDF and images.
2. The Pilates reformer level grouping is Palee's own; only the order is sourced.
3. The Dan John standards are from secondhand copies.
4. The strongman novice loads come from a single UK contest.
5. The Higdon half-marathon peak long run (10 mi) is inferred.
6. No Greek federation sources were checked. The Greek text uses the English exercise names that Greek athletes commonly use (Pilates names, strongman implements, CMS/MS).
7. HYROX notes gathered before the scope change were not used. In short: Open and Pro singles, Doubles, Relay (Open weights only). Pro sled push is 202 kg for men and 152 kg for women. Reports say Women Open wall balls drop to 75 reps in 2025/26, which is unverified.

## Appendix C: full source notes and links of the helper templates

The `system` line in the app is a short label; these are the full notes.

- **tap_istd**: ISTD (Imperial Society of Teachers of Dancing) Tap Faculty graded and vocational examinations: Pre-Primary and Primary class exams then Grades 1-6 (Ofqual regulated) then vocational Intermediate · Advanced 1 · Advanced 2. Step vocabulary per grade taken from the ISTD Tap syllabus outline (April 2023 issue). Minimum ages: Pre-Primary/Primary 5 · Grade 1 6 · Intermediate 13 (recommended). Alternatives: IDTA Tap grades · BATD Tap · RAD has no tap. Advanced 1 syllabus was revised from 1 Oct 2026; content here follows the 2023 outline.
  Sources: https://www.istd.org/documents/tap-syllabus-outline-april-2023/1tap-syllabus-outline-april-2023.pdf · https://www.istd.org/dance/dance-genres/tap/tap-examinations-and-qualifications/ · https://istd.org/examinations/theatre-dance-syllabus-outlines
- **jazz_istd_modern_theatre**: ISTD Modern Theatre Faculty (the UK exam syllabus for jazz/theatre jazz): Primary then Grades 1-6 then vocational Intermediate Foundation · Intermediate · Advanced 1 · Advanced 2. Vocabulary from the ISTD Modern Theatre Specification S01000 v1.1 (July 2026). Minimum ages: Primary 5 · Grade 1 6 · Intermediate Foundation/Intermediate 13 (recommended). Alternatives: IDTA Freestyle/Jazz grades · BATD Jazz · ISTD Modern Theatre Jazz Awards (Bronze/Silver/Gold) · US college jazz proficiency levels (beginner/intermediate/advanced). Grades 1-3 detail is partly summarised.
  Sources: https://www.istd.org/documents/modern-theatre-primary-class-examinations-jazz-awards-grades/istd-modern-theatre-specification-s01000-v1.1-july-2026.pdf · https://istd.org/examinations/theatre-dance-syllabus-outlines · https://www.dance.uga.edu/sites/default/files/Jazz%20Dance%20Proficiency%20Standards.pdf
- **ballet_cecchetti**: ISTD Cecchetti Classical Ballet Faculty (UK; also Cecchetti Society/Cecchetti Council of America and Cecchetti Ballet Australia use similar ladders). Graded path: Pre-Primary · Primary · Grades 1-6 then vocational Intermediate Foundation · Intermediate · Advanced 1 · Advanced 2 then Enrico Cecchetti Diploma (teacher/professional level · omitted). A parallel class-exam path exists (Standards 1-6 · Senior Certificates 1-2). Content from the ISTD Cecchetti syllabus outline (July 2024). Minimum ages: Pre-Primary/Primary 5 · Grades 1-2 7 · G3 8 · G4 9 · G5 10 · G6 11 · Int Foundation 11 · Intermediate 12 · Adv 1 13 · Adv 2 14.
  Sources: https://istd.org/documents/cecchetti-classical-ballet-syllabus-outline-july-2024/syllabus-outline-cecchetti-classical-ballet-july-2024.pdf · https://www.istd.org/documents/cecchetti-grades-vocational-class-examinations-and-cecchetti/istd-cecchetti-specification-v2.0.pdf · https://www.cecchetti.org/students/syllabus-overview/
- **ballet_vaganova**: Vaganova Academy of Russian Ballet 8-year professional programme (classes 1-8 · entry around age 10). Year contents reconstructed from Kostrovitskaya '100 Lessons in Classical Ballet: the eight-year program of Leningrad's Vaganova Choreographic School' and Vaganova 'Basic Principles of Classical Ballet' as summarised by teacher-training programmes (Classical Dance Alliance 6-year compression) and conservatory syllabi. Exact year placement of some steps varies by school and edition. No examining-body 'grades' exist; schools outside Russia often run Vaganova Levels 1-8 (or Preparatory + 1-8). Boys/girls differences noted in skills.
  Sources: https://www.goodreads.com/book/show/9145.100_Lessons_in_Classical_Ballet · https://classicaldancealliance.org/six-year-syllabus-overview · https://learnballetonline.teachable.com/p/vaganovaballetlevelone · https://accademialascala.it/systemFiles/htmleditor/upload_dir/triennio-danza/programs-i-2024.pdf
- **kizomba_palee**: No federation or examining body grades kizomba. Palee levels built from common school curricula (beginner/intermediate/advanced course outlines) and widely taught Angolan/Portuguese step names (passo básico · saída · retrocesso · vírgula · 3x3 · kota from semba). Urban kiz and tarraxinha are treated as later styling. Some teachers reject a fixed 'basic step' and teach musical walking instead.
  Sources: https://iknowhow.teachable.com/p/kizomba-beginners-intermediate-advanced · https://snowmotion.punchpass.com/classes/18549416 · https://ycvdance.punchpass.com/series/26074
- **zumba_dance_fitness_palee**: Zumba has instructor licensing (Zumba Basic 1 on the four core rhythms merengue · salsa · cumbia · reggaeton and the Zumba formula; Basic 2 adds more rhythms) but no member grades. Palee member levels built on the Basic 1 core-rhythm structure plus commonly added rhythms (bachata · cha-cha · samba · soca · bhangra · belly dance · hip-hop) and fitness milestones. Also fits other dance fitness formats (e.g. Sh'Bam · Bokwa).
  Sources: https://www.zumba.com/en-US/training/2026-10-14_B1_Maipu_CL_Rodrigo_Diaz · https://nas.com/zumba/events/zumba-basic-1 · https://livestrong.com/article/259945-basic-zumba-moves
- **aerial_hammock_yoga_palee**: No governing body grades aerial hammock or aerial yoga for students (teacher trainings such as AYOGA · Unnata · AntiGravity exist). Studios typically run Level 0/Intro then Levels 1-3 with approval to move up (e.g. straddle and diamond inversions before Level 2; pullover to swan · bomb drop and waterfall for Level 2/3). Palee levels follow that common studio progression.
  Sources: https://serpentinestudios.punchpass.com/classes/17018319 · https://aerialrevolution.pike13.com/e/285586701 · https://wildheart-aerial-school.teachable.com/courses/768872 · https://everosestudios.offeringtree.com/offerings/aerial-yoga-level-1-2-pearl?embed=true
- **wrestling_palee**: No belt or grade system in Olympic wrestling (UWW). Countries use competition classes (e.g. Russian/Greek sports ranks · US age-group medals) and coach-education levels (USA Wrestling Copper/Bronze/Silver/Gold are for coaches). Wrestling Canada once ran a Bronze/Silver/Gold participant skill award (page no longer online). Palee levels are organised around USA Wrestling's seven basic skills (stance · motion · level change · penetration · lifting · back step · back arch) then takedowns · par terre and competition skills.
  Sources: https://content.usawmembership.com/articles/2175 · https://en.wikipedia.org/wiki/Collegiate_wrestling_moves · https://archive.teamusa.com/usa-wrestling/coaches/ncep-certification.html · https://fivepointmove.com/?p=18960
- **sambo_fias**: FIAS Belt System (International Sambo Federation · belt.sambo.sport): Beginner (no stripe) · Student Levels 1-6 (coloured stripes on the red/blue competition belt) · Candidate for Master · Master · Grand Master. FIAS states stripes range from white to burgundy/purple but the per-level colour is not published openly · so colours are null. Technique lists for Beginner and Student Levels 1-3 are taken from the FIAS belt site; Student Levels 4-6 are a Palee extension (FIAS has not published them openly) and should be checked. Grand Master (honorary) omitted. Alternative: Russian sports ranks (youth ranks · 3rd-1st adult · CMS · Master of Sport).
  Sources: https://belt.sambo.sport/ · https://belt.sambo.sport/lessons/junior · https://belt.sambo.sport/lessons/1st_rank · https://belt.sambo.sport/lessons/2_rank · https://belt.sambo.sport/lessons/3_rank · https://sambo.sport/en/news/fias-zapustila-ofitsialnyy-sayt-poyasnoy-sistemy/
- **strongman_palee**: No federation runs an athlete level ladder for strongman (contests use bodyweight/novice/open classes). Palee levels follow the standard event categories (deadlift · overhead · squat · stones · carries · yoke · throws · flips · loading · medleys) and the novice-to-open contest pathway. Only sourced loads: UK novice contest u95 kg (farmers 100 kg x 25 m · log 70 kg max reps 75 s · yoke 200 kg x 25 m) cited as reference. All other targets are technique/completion criteria; loads are set by the coach per bodyweight class.
  Sources: https://fitnessvolt.com/strongman/events/ · https://fitnessvolt.com/strongman/strength-standards/ · https://www.sugdenbarbell.co.uk/competitions/KRUNCHMANIA-Novice-Strongman-Competition-(under-95kg-and-over-95kg)-402 · https://legendarystrength.com/lessons-in-strongman-training/ · https://www.strengthshop.co.uk/blogs/news/strongman-equipment
- **kettlebell_hardstyle**: StrongFirst certifies instructors (SFG I) not students so Palee levels are built from its standards. Sourced numbers: SFG I six skills (swing 10/side · double clean 5 · press 5/side · double front squat 5 · snatch 5/side · get-up 1/side) and snatch test 100 reps in 5 min with bell by sex and bodyweight (women 12 kg up to 59 kg else 16 kg · men 20 kg up to 68 kg · 24 kg to 100 kg · 28 kg over). Simple & Sinister (Pavel Tsatsouline): 100 one-arm swings in 5 min plus 10 get-ups in 10 min; Simple = men 32/32 kg · women 24 kg swing 16 kg get-up; Sinister = men 48/48 · women 32/24 (LiftVault summary of the book). Lower-level rep targets are Palee coaching defaults.
  Sources: https://www.strongfirst.com/certifications/sfg-i-requirements/ · https://www.strongfirst.com/strongfirst-sfg-kettlebell-certification-prep-guide/ · https://www.strongfirst.com/sinister/ · https://liftvault.com/programs/strength/simple-sinister-kettlebell-program-spreadsheet-pavel/ · https://www.strongfirst.com/beyond-sinister/
- **kettlebell_sport_ranks**: Russian-origin rank ladder used by IUKL/IKO and national federations: Rank 3 · Rank 2 · Rank 1 · CMS · MS · MSIC (IKMF also awards HMS · MSWC · MS · CMS for marathon). Each rank is earned by reaching a rep total in a 10-min set (some tables also 5-min) for the lifter's sex · bodyweight class · bell weight; the exact thresholds live in the IKO 2024 ranking table PDF and were NOT reproduced here. Sourced bell weights (IUKL via FFForce 2025): amateur seniors B men 24 kg · women 16 kg; professional seniors A men 32 kg · women 24 kg; U-18 boys 24 / girls 16; U-16 boys 16 / girls 12. Classic events: jerk · long cycle · snatch (one hand change) · biathlon (jerk then snatch).
  Sources: https://kettlebellworld.org/ranking-tables · https://ikmf-world.com/rules/ranks-and-rules · https://www.ffforce.fr/medias/fichiers/Saison%202025/KETTLEBELL/Arbitrage/2025_00_R%C3%A8glement%20sportif%20international%20et%20national.pdf · https://en.wikipedia.org/wiki/Kettlebell_lifting · https://www.kettlebellkings.com/blogs/default-blog/intro-to-kettlebell-sport-part-4-the-kettlebell-sport-long-cycle
- **running_palee**: No federation level ladder for recreational runners (England Athletics levels are for leaders/coaches). Palee levels follow the NHS Couch to 5K plan (9 weeks · 3 runs/week · ends with 30 min continuous running; week 1 = 1 min run / 1.5 min walk x8 with 5-min walk warm-up and cool-down) then distance steps 10K → half (Hal Higdon Novice 1 half · 12 weeks) → marathon (Higdon Novice 1 · 18 weeks · long runs 6→20 miles · 4 run days + cross-training). Distances and plan lengths are sourced; other targets are Palee coaching criteria (no pace numbers invented).
  Sources: https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan/ · https://www.trainingpeaks.com/training-plans/running/marathon/tp-139218/hal-higdon-marathon-novice-1 · https://trainingpeaks.com/blog/moving-up-from-the-10k-to-half-marathon · https://runningwithrock.com/hal-higdon-marathon-training-plan/ · https://www.parkrun.org.uk/
- **road_cycling_palee**: First three Palee levels mirror the UK National Standard for Cycle Training / Bikeability: Level 1 = Roles 1-2 in traffic-free space (bike check · control · look behind · signal); Level 2 = Roles 1-4 on simple roads and junctions; Level 3 = Roles 1-4 on complex busier roads. Group riding · endurance and performance levels are Palee-designed from common club practice; British Cycling Go-Ride has no single national rider award ladder. 100 km is the widely used 'metric century' sportive distance; FTP 20-min test is a widely standard field test.
  Sources: https://assets.publishing.service.gov.uk/media/5faaa059e90e073062910954/national-standard-cycling-document.pdf · https://professionals.bikeability.org.uk/download/704 · https://www.cyclinguk.org/article/what-bikeability · https://www.bikeabilitywales.org.uk/national-standards · https://www.ppycc.org.uk/?p=10763
- **indoor_cycling_palee**: Instructor programmes (Spinning · Schwinn · Stages) certify coaches not riders. Palee levels are built from common class movements (seated flat · seated climb · standing climb · jumps · sprints) and the cadence envelope cited by Wikipedia (flat/jumps ~80-110 rpm · climbs ~60-80 rpm; Spinning bases cadence on outdoor riding). FTP 20-min test and RPE/HR zones are widely standard.
  Sources: https://en.wikipedia.org/wiki/Indoor_cycling · https://spinning.com/understanding-cadence-indoors-and-out/ · https://www.heartzones.com/?p=77 · https://www.24hourfitness.com/24life/fitness/2016/speed-vs-resistance-on-the-indoor-bike
- **indoor_rowing_palee**: British Rowing Go Row Indoor technique areas (posture · grip · recovery · catch · drive · finish) and Concept2 drills (arms-and-body · pauses · counting rhythm · legs only) structure the first levels; drive sequence legs-body-arms and recovery reverse with recovery about twice the drive time are from British Rowing/Concept2. No rower level ladder exists; 2k/5k/30-min tests and Concept2 online ranking are widely standard benchmarks (no times invented).
  Sources: https://www.britishrowing.org/indoor-rowing/go-row-indoor/how-to-indoor-row/british-rowing-technique/ · https://www.concept2.com/indoor-rowers/training/technique-videos/rowing-drills · https://www.britishrowing.org/knowledge/online-learning/techniques-and-training/water-rowing-technique/ · https://crossfit.com/essentials/rowing-the-pick-drill · https://log.concept2.com/rankings/2022/rower/2000
- **pilates_mat_classical**: No governing body sets student levels; Palee uses the widely taught classical Basic · Intermediate · Advanced mat orders (Pilatesology order sheets with reps) derived from Joseph Pilates' 34 exercises in Return to Life Through Contrology. Fundamentals level (breath · neutral/imprint · pelvic curl) is Palee-designed from common pre-Pilates teaching. Reps quoted are from the Pilatesology sheets.
  Sources: https://pilatesology.com/wp-content/uploads/2024/04/Classical-Mat-Exercises-Basic-Intermediate-Advanced-With-LINKS.pdf · https://onlinepilatesclasses.com/blog/the-original-34-classical-pilates-mat-exercises · https://www.pilatesanytime.com/blog/legacy/understanding-return-to-life · https://blog.alomoves.com/movement/original-34-pilates-exercises
- **pilates_reformer_classical**: Exercise names and their sequence come from the classical Universal Reformer order (Online Pilates Classes · 46 items from Footwork to Russian Squat). The split into Basic · Intermediate · Advanced is Palee's own grouping following the classical convention that basic students do a short subset and advanced exercises (headstands · control balance · splits) come last; Pilatesology publishes separate basic/intermediate/advanced reformer orders that could refine it. BASI Block System is an alternative contemporary structure.
  Sources: https://onlinepilatesclasses.com/blog/full-pilates-reformer-order-and-tutorial/ · https://pilatesology.com/?p=233603 · https://www.basipilates.com/innovation/basi-block-system/ · https://www.clubpilates.com.au/pilates/pilates-reformer-exercises-from-beginner-to-advanced/
- **mobility_flexibility_palee**: No standard level system. Palee levels combine Functional Range Conditioning practice (daily CARs; PAILs/RAILs paired; end-range strength) with the common block-to-floor front-split progression and the glute bridge → full bridge → stand-down/stand-up back-bend progression. All hold times are Palee coaching defaults (no federation numbers); the 'full' shapes (floor splits · chest-to-floor pancake · stand-up bridge) are widely standard goals.
  Sources: https://theprehabguys.com/intro-to-frc/ · https://anaritaalmeida.substack.com/p/understanding-frc-and-how-it-is-a · https://gymnasticshq.com/how-to-do-a-split/ · https://www.kangaroohoppers.com/blogs/news/how-to-do-the-splits · https://triyoga.co.uk/blog/exploring-functional-range-conditioning-frc-unlocking-the-potential-of-your-body/
- **hiit_bootcamp_palee**: No level system exists. Palee levels progress interval structure using ACE guidance (beginner 30:15 work:rest at RPE 4-6; progress by +5-10 s work or -10-15 s rest) up to the Tabata 20:10 x8 format (widely standard; considered too hard for true beginners). Movement standards (squat · push-up · burpee · lunge · plank · sprint) are common bootcamp content; rep counts are Palee default targets a coach can edit. Also usable for bootcamp and circuit_training.
  Sources: https://www.acefitness.org/education-and-resources/professional/expert-articles/5880/a-basic-high-intensity-interval-training-routine-for-beginning-exercisers · https://www.weightwatchers.com/us/blog/hiit-workouts-for-beginners · https://www.weightlossresources.co.uk/exercise/plans/beginners-hiit-workouts.htm
- **strength_training_palee**: Palee levels follow the novice → advanced novice → intermediate → advanced stages popularised by Rippetoe's Practical Programming (novice adds load every session · intermediate progresses weekly · advanced over longer blocks). Bodyweight-relative 'expected' and 'game changer' standards attributed to Dan John (deadlift 1.5x and 2x bodyweight · 15 pull-ups · bodyweight bench and squat x15) come from secondhand forum copies and are flagged as reference only. Powerlifting meet classification is covered by a separate template.
  Sources: https://fitnessvolt.com/starting-strength-lp/ · https://www.goodreads.com/book/show/20765602-practical-programming-for-strength-training · https://www.strongfirst.com/community/threads/dan-johns-strength-standards.2313/ · https://savagezen.substack.com/p/strength-and-conditioning-standards-for-athletes · https://www.otpbooks.com/otp-vault-dan-john-strength-standards-warmups-and-complexes

## Appendix D: the curriculum of every template

Generated from the catalogue (English message ids; Greek is in `apps/api/priv/gettext/el/LC_MESSAGES/rank_templates.po`). Days and classes are the minimums between ranks where a source states them.

### Combat

#### BJJ belts (`bjj_adult`, federation)
IBJJF adult belts (16+)

- **White** (white): Tapping and mat etiquette
- **Blue** (blue): Age 16 or older (IBJJF); Break-falls back and to the side; Shrimp and bridge escapes to both sides; Closed guard posture and guard break; Mount escape with upa and elbow-knee; Side control escape to guard; Scissor sweep and hip-bump sweep; Armbar and triangle from closed guard; Rear naked choke from back control; Knee-cut or toreando guard pass; Double-leg or single-leg takedown; Positional sparring with control
- **Purple** (purple), 730 days: Open guard retention (De La Riva or spider); Half guard sweeps (old school and deep half); Butterfly guard sweeps and elevations; Three guard passes chained together; Back take from turtle and seatbelt control; Collar chokes from mount and back; Kimura and americana from top and bottom; Live rolls with a clear game plan
- **Brown** (brown), 540 days: Age 18 or older (IBJJF); Connected attacks from a personal guard game; Leg-lock entries and straight ankle lock; Counters to the common guard passes; Pressure passing and smash half guard; Omoplata and wrist lock; Helps teach white belts
- **Black** (black), 365 days: A complete game in every position; Chains submissions and transitions fluidly; Heel hook defence and no-gi adaptations; Competition-level takedowns; Can teach the whole curriculum; Age 19 or older (IBJJF)

#### BJJ kids belts (`bjj_kids`, federation)
IBJJF kids belts (ages 4-15)

- **White** (white): Tapping and mat etiquette
- **Grey-white** (grey): Safe backward break-fall; Shrimp and bridge; Technical stand-up
- **Grey** (grey): Hold side control for 10 seconds; Mount escape with upa; Closed guard posture in both roles
- **Grey-black** (grey): Scissor sweep; Armbar from mount; Side control escape to guard
- **Yellow-white** (yellow): Age 7 or older (IBJJF); Hip-bump sweep; Guard pass to side control; Knee on belly
- **Yellow** (yellow): Triangle from closed guard; Back control with hooks; Double-leg takedown
- **Yellow-black** (yellow): Back control escape; Kimura from guard; Butterfly sweep
- **Orange-white** (orange): Age 10 or older (IBJJF); Collar choke from mount; Half guard sweep; Turtle defence
- **Orange** (orange): Sweep to submission combination; Two guard passes; Osoto-gari or single-leg takedown
- **Orange-black** (orange): Arm drag to back take; Back take from turtle; Positional sparring with a plan
- **Green-white** (green): Age 13 or older (IBJJF); Open guard retention; Bow and arrow choke; Counter to a guard pass
- **Green** (green): Three attacks chained from guard; Cross collar choke from guard; Helps younger children drill
- **Green-black** (green): Whole kids curriculum in live sparring; At 16 moves to adult blue or purple belt (coach decides)

#### Karate belts (`karate_kyu`, palee)
Palee 7-belt kyu ladder (no single federation)

- **White** (white): Dojo etiquette (rei and seiza)
- **Yellow** (yellow): Stances zenkutsu and kiba-dachi; Oi-zuki and gyaku-zuki; Age-uke and gedan-barai; Mae-geri; First kata (Taikyoku or Heian Shodan)
- **Orange** (orange): Kokutsu-dachi and shuto-uke; Soto-uke and uchi-uke; Mawashi-geri; Gohon kumite (five-step sparring); Heian Nidan
- **Green** (green): Yoko-geri keage and kekomi; Combinations of three techniques; Sanbon kumite (three-step sparring); Heian Sandan
- **Blue** (blue): Ushiro-geri; Kihon ippon kumite; Heian Yondan and Godan
- **Brown** (brown): Jiyu ippon kumite; Tekki Shodan and Bassai Dai; Controlled free sparring (jiyu kumite)
- **Black** (black): All kihon with power and control; A senior kata of choice with bunkai; Free sparring against two opponents in turn

#### Shotokan karate kyu (`karate_shotokan_kyu`, federation)
Shotokan kyu (shoto.uk colours and intervals)

- **Beginner** (white): Dojo etiquette and dojo kun
- **Kyu 10** (red), 90 days: Zenkutsu-dachi with oi-zuki; Age-uke soto-uke and gedan-barai; Mae-geri keage
- **Kyu 9** (orange), 90 days: Kata Heian Shodan; Uchi-uke and shuto-uke in kokutsu-dachi
- **Kyu 8** (yellow), 90 days: Mawashi-geri; Gohon kumite jodan and chudan; Kata Heian Nidan
- **Kyu 7** (green), 90 days: Yoko-geri keage and kekomi in kiba-dachi; Kizami-zuki and gyaku-zuki combination; Sanbon kumite; Kata Heian Sandan
- **Kyu 6** (blue), 90 days: Ushiro-geri; Kihon ippon kumite; Kata Heian Yondan
- **Kyu 5** (purple), 90 days: Combinations with stance changes; Kihon ippon kumite with counter; Kata Heian Godan
- **Kyu 4** (purple), 90 days: Mawashi-geri and ura-mawashi-geri; Jiyu ippon kumite; Kata Tekki Shodan
- **Kyu 3** (brown), 180 days: Kihon with hip rotation and kime; Jiyu ippon kumite on all levels; Kata Bassai Dai
- **Kyu 2** (brown), 180 days: Controlled jiyu kumite; Kata Kanku Dai or Jion
- **Kyu 1** (brown), 180 days: Jiyu kumite with timing and distance; Kata Enpi or Jitte with bunkai
- **Dan 1** (black), 365 days: All kihon with kime; Tokui kata (own choice) and a set kata; Jiyu kumite

#### Kyokushin karate kyu (`karate_kyokushin_kyu`, federation)
Kyokushin kyu colours (IKO intervals)

- **White** (white): Dojo etiquette and seiza
- **Kyu 10** (orange), 90 days: Seiken and uraken strikes; Mae-geri and hiza-geri; Kata Taikyoku Sono Ichi
- **Kyu 9** (orange), 90 days: Mawashi-geri gedan and chudan; Basic blocks in zenkutsu-dachi; Kata Taikyoku Sono Ni and San
- **Kyu 8** (blue), 90 days: Yoko-geri and kakato-geri; Kata Pinan Sono Ichi; Light kumite rounds
- **Kyu 7** (blue), 90 days: Combination punching on pads; Kata Pinan Sono Ni
- **Kyu 6** (yellow), 90 days: Ushiro-geri; Kata Pinan Sono San and Sanchin; Full-contact kumite (two rounds)
- **Kyu 5** (yellow), 90 days: Kata Pinan Sono Yon; Conditioning: 50 push-ups on knuckles
- **Kyu 4** (green), 90 days: Jodan mawashi-geri; Kata Pinan Sono Go and Gekisai Dai; Kumite five rounds
- **Kyu 3** (green), 90 days: Kata Tsuki no Kata and Yantsu; Tameshiwari (breaking) when the club tests it
- **Kyu 2** (brown), 90 days: Kata Saiha and Tensho; Kumite eight rounds
- **Kyu 1** (brown), 90 days: Kata Gekisai Sho and Bassai Dai; Helps teach the junior grades
- **Dan 1** (black): All kyu kata and kihon; Kumite of 10 or more rounds

#### Judo belts (`judo_kyu`, federation)
European kyu colours with British Judo intervals

- **White** (white): Bow (rei) and judogi care; Ukemi back and side
- **Yellow** (yellow), 30 days: Ukemi forward rolling; O-soto-gari and o-goshi; Hiza-guruma and de-ashi-barai; Kesa-gatame and escape; Kumikata (grips) and tsukuri
- **Orange** (orange), 90 days: Ippon-seoi-nage and tai-otoshi; O-uchi-gari and ko-uchi-gari; Yoko-shiho-gatame and kami-shiho-gatame; Randori standing and on the ground
- **Green** (green), 90 days: Harai-goshi and uchi-mata; Combination throws (renraku-waza); Turnovers into hold-downs; Juji-gatame (no submission under 16)
- **Blue** (blue), 90 days: Counter throws (kaeshi-waza); Shime-waza (no submission under 16); Nage-no-kata first set
- **Brown** (brown), 90 days: Sumi-gaeshi and tomoe-nage; Tokui-waza in randori; Nage-no-kata three sets
- **Black** (black): Nage-no-kata complete; Katame-no-kata; Competition or shiai points as the federation requires; Age 15 or older

#### Taekwondo belts (`taekwondo_geup`, federation)
Kukkiwon 10 geup to 1st dan (British Taekwondo intervals)

- **Geup 10** (white): Dojang etiquette and stances
- **Geup 9** (white), 90 days: Ap seogi and ap kubi; Momtong jireugi and arae makki; Ap chagi
- **Geup 8** (yellow), 90 days: Poomsae Taegeuk Il Jang; Bandal chagi
- **Geup 7** (yellow), 90 days: Poomsae Taegeuk Ee Jang; Yeop chagi
- **Geup 6** (green), 90 days: Poomsae Taegeuk Sam Jang; Dollyeo chagi to body and head; Step sparring
- **Geup 5** (green), 90 days: Poomsae Taegeuk Sa Jang; Dwi chagi
- **Geup 4** (blue), 90 days: Poomsae Taegeuk Oh Jang; Kyorugi with protectors
- **Geup 3** (blue), 90 days: Poomsae Taegeuk Yuk Jang; Naeryeo chagi
- **Geup 2** (red), 90 days: Poomsae Taegeuk Chil Jang; Spinning kicks (dwi huryeo chagi)
- **Geup 1** (red), 90 days: Poomsae Taegeuk Pal Jang; Board breaking
- **Dan 1** (black), 180 days: All Taegeuk poomsae and Koryo; Kyorugi and self-defence (hosinsul); Poom instead of dan under age 15 (Kukkiwon)

#### Aikido kyu (`aikido_kyu`, federation)
Aikikai Hombu practice days per grade

- **Beginner** (white): Ukemi forward and backward
- **Kyu 5** (white), 30 classes: Shomen-uchi ikkyo omote and ura; Katate-dori shiho-nage; Shomen-uchi irimi-nage; Tai no henko and kokyu-dosa
- **Kyu 4** (white), 40 classes: Shomen-uchi nikyo and sankyo; Katate-dori kote-gaeshi; Suwari-waza kokyu-ho
- **Kyu 3** (white), 50 classes: Chudan-tsuki kote-gaeshi; Ryote-dori tenchi-nage; Yokomen-uchi shiho-nage and irimi-nage; Shomen-uchi yonkyo
- **Kyu 2** (white), 50 classes: Suwari-waza ikkyo to yonkyo; Hanmi handachi shiho-nage; Ushiro waza from several grabs
- **Kyu 1** (white), 60 classes: Ushiro ryote-dori kote-gaeshi; Jiyu-waza against one attacker; Tanto-dori basics (dojo addition)
- **Dan 1** (black), 70 classes: Age 15 or older (Aikikai); All kyu techniques fluidly; Randori against two attackers (dojo addition)

#### Muay Thai khan (`muay_thai_khan`, federation)
Kru Muay Thai Association khan 1-10

- **Khan 1** (white): Fighting stance and footwork; Jab cross hook uppercut; Wai kru ram muay respect
- **Khan 2** (yellow): Teep (front kick) both legs; Roundhouse kick to body both sides; Check (block) a low kick
- **Khan 3** (yellow): Straight knee and diagonal knee; Horizontal and upward elbows; Combinations of four on pads
- **Khan 4** (green): Clinch entry and neck control; Catch a kick and counter; Technical sparring three rounds
- **Khan 5** (green): Switch kick and switch knee; Clinch knees and off-balancing; Teep defence and counter
- **Khan 6** (blue): Spinning elbow and back elbow; Sweeps from the catch; Sparring five rounds
- **Khan 7** (blue): Ram muay performed in full; Feints and rhythm changes
- **Khan 8** (brown): Ring craft and cutting off the ring; Holds pads for others
- **Khan 9** (brown): Interclub bout or full sparring test; Explains the history of Muay Thai
- **Khan 10** (red), 217 classes: At least 217 hours of training in total (KMA); Assists teaching a class; Builds a pad round for a beginner

#### Kickboxing belts (`kickboxing_wako`, federation)
WAKO grading programme (2025)

- **White** (white): Guard stance and footwork
- **Yellow** (yellow), 180 days: Jab cross hook uppercut; Front kick and roundhouse kick; Knee strikes and low kick to the thigh; Parry and block straight punches
- **Orange** (orange), 180 days: Side kick and hook kick to the head; Slip and roll under punches; Three-technique combinations
- **Green** (green), 180 days: Back kick; Counter-attacks after defence; Light sparring two rounds
- **Blue** (blue), 180 days: Jumping spinning back side kick and jumping spinning hook kick; Kick catching defence; Sparring three rounds in point or light contact
- **Brown** (brown), 180 days: Jumping kicks with rotation; Ring and tatami tactics; Free sparring
- **Black** (black), 365 days: Axe kick external and internal; Full technical exam of all colours; Written paper on kickboxing history; Age 16 or older in the year of grading

#### Boxing levels (`boxing_awards`, federation)
Modelled on England Boxing awards

- **Level 1**: Stance and guard; Step forward back and sideways; Jab to the head and body
- **Level 2**: Cross and lead hook; Parry and block the jab; Shadow boxing one round
- **Level 3**: Uppercuts both hands; Slip and roll; Four-punch combinations on pads
- **Level 4**: Conditioned sparring (one hand or set attack); Counter-punching after defence
- **Level 5**: Technical sparring two rounds; Ring craft: angles and the ropes
- **Level 6**: Full sparring three rounds; Knows amateur boxing rules and scoring

#### MMA levels (`mma_levels`, palee)
Palee gym progression (no federation ranks)

- **Level 1**: Stance and footwork for striking; Basic punches and kicks; Break-falls and shrimping
- **Level 2**: Double-leg and single-leg takedowns; Sprawl and takedown defence; Guard and mount escapes
- **Level 3**: Cage wall work (pin and escape); Ground and pound from guard and mount; Rear naked choke and guillotine
- **Level 4**: Striking to takedown chains; Getting up from bottom position; MMA sparring with light contact
- **Level 5**: Full MMA sparring three rounds; Game plan for an amateur bout; Knows the unified rules

#### Krav Maga grades (P G E) (`krav_maga_grades`, federation)
IKMF/KMG Practitioner Graduate Expert

- **P1**: Fighting stance and movement; Straight punches palm strikes and front kick; 360 outside defence; Release from front choke
- **P2**: Elbows and knees; Inside defences against punches; Choke releases from behind and side; Break-falls
- **P3**: Defences against hooks and uppercuts; Bear hug releases; Ground fighting basics
- **P4**: Defence against kicks; Headlock releases; Fighting under stress drills
- **P5**: Knife threat defences (static); Stick attack defences; Multiple attacker awareness
- **G1**: Knife attack defences (overhead and stab); Gun threat from front; Third-party protection basics
- **G2**: Gun threats from side and behind; Advanced ground defences
- **G3**: Knife and stick combined scenarios; Defending while seated or in a vehicle
- **G4**: Long-gun and rifle threats; Fighting several attackers
- **G5**: All practitioner and graduate syllabi under stress; Scenario training in low light
- **E1** (black): Expert exam: complete syllabus at speed; Endurance fight test

#### Krav Maga belts (`krav_maga_belts`, federation)
FEKM colour belts (at most one a year)

- **White** (white): Fighting stance and safety rules
- **Yellow** (yellow), 365 days: Punches palm strikes elbows knees; Front and round kicks; 360 outside defence and inside defences; Choke releases front side and back
- **Orange** (orange), 365 days: Defences against hooks and kicks; Bear hug and headlock releases; Ground escapes from mount and guard
- **Green** (green), 365 days: Knife threat and stab defences; Stick defences; Fighting from the ground to standing
- **Blue** (blue), 365 days: Handgun threats from all angles; Multiple attacker drills
- **Brown** (brown), 365 days: Rifle threats and third-party protection; Scenario and stress tests
- **Black** (black), 365 days: Complete syllabus under fatigue; Teaching ability

#### Kung fu sashes (`kung_fu_sash`, palee)
Palee sash ladder (styles and colours vary)

- **White** (white): Horse stance bow stance cat stance
- **Yellow** (yellow): Basic punches palms and blocks; Front snap and side kicks; First form of the school
- **Orange** (orange): Stance transitions with balance; Sweeps and low stances (pu bu); Second form
- **Green** (green): Jumping front kick and tornado kick; Partner drills (two-person set); Third form
- **Blue** (blue): Applications of the forms; Light sanda sparring; First weapon (staff)
- **Brown** (brown): Advanced form; Second weapon (broadsword or spear); Chin na basics
- **Red** (red): All forms with power and spirit; Sanda sparring three rounds
- **Black** (black): Complete syllabus and a demonstration; Assists teaching

#### Wing Chun levels (`wing_chun_forms`, federation)
Ip Man lineage form order

- **Siu Nim Tao**: Yee jee kim yeung ma stance; Centre-line theory and chain punch; Siu Nim Tao form; Tan pak and bong sau
- **Chum Kiu**: Chum Kiu form; Turning stance and stepping; Dan chi sau and luk sau (poon sau); Front and side kicks
- **Biu Tze**: Biu Tze form; Chi sau with attacks; Emergency techniques and elbows
- **Mook Yan Jong**: Wooden dummy form (116 movements); Free chi sau
- **Luk Dim Boon Kwan**: Long pole form; Pole drills with a partner
- **Baat Cham Dao**: Butterfly knives form; Teaches the empty-hand forms

#### Capoeira cords (`capoeira_cords`, federation)
Brazilian Capoeira Confederation student cords

- **No cord yet**: Ginga; Basic esquivas (cocorinha and negativa)
- **Green cord** (green): Batizado: plays in the roda for the first time; Meia-lua de frente and armada; Queixada and benção; Au (cartwheel) and role
- **Yellow cord** (yellow): Martelo and meia-lua de compasso; Sings a corrido and claps the rhythm; Plays pandeiro and atabaque basics
- **Blue cord** (blue): Rasteira and other take-downs; Basic berimbau toques; Angola rhythm game
- **Green-yellow cord** (green): Roda game at Regional rhythm; Floreios (macaco and au sem mao)
- **Green-blue cord** (green): Leads a song in the roda; Sequences of Mestre Bimba
- **Yellow-blue cord** (yellow): Plays every instrument of the bateria; History of capoeira and its mestres
- **Green-yellow-blue cord** (blue): Formado: age 18 or older and 5 years of capoeira (CBC); Teaches beginners under supervision

#### Wrestling (`wrestling_levels`, palee)
Palee levels (Olympic wrestling has no grades)

- **Novice**: Square and staggered stance with head up; Stance motion forward · back and sideways without crossing feet; Level change from stance; Forward and backward rolls; Front and back neck bridge (safe); Breakfall to the side and back; Sprawl from stance; Collar tie and inside control ties; Knows scoring basics: takedown · exposure · fall; Skin check and mat hygiene routine
- **Basic Skills**: Penetration step (drop step) to a partner; Outside step penetration; Knee spin penetration; Lift a partner from a level change; Back step drill; Back arch drill on a crash pad; Hand fighting: clear ties and win inside position; Snap down to front headlock; Referee's position top and bottom (par terre); Hip heist from bottom
- **Takedowns**: Double leg takedown with finish; Single leg takedown with finish; High crotch; Arm drag to back or single; Duck under; Ankle pick; Front headlock go-behind; Sprawl and whizzer defence; Re-attack after a failed shot; Push-out awareness at the edge
- **Mat Wrestling**: Gut wrench both directions; Leg lace (ankle lace) turn; Half nelson to pin; Cradle (near side and far side); Stand-up from bottom; Sit-out and turn-in; Switch reversal; Bridging out of a pin; Defends gut wrench and leg lace from bottom; Pin combination: tilt to cradle
- **Advanced**: Hip toss (headlock or over-under); Arm throw; Body lock and lateral drop; Front body lock lift and suplex (Greco-Roman); Reverse body lock lift from par terre; Underhook and 2-on-1 tie series; Counter to single leg (heel lift and step over); Scramble from a stalled shot; Chain wrestling: 3 linked attacks; Weight management and safe cutting knowledge
- **Competitor**: Full 2 × 3 minute match at competition pace; Knows UWW rules: passivity · activity clock · cautions; Personal A-game of 2 takedowns and 1 turn; Scouts and adjusts tactics between periods; Leads warm-up and drills for juniors; Competes in an official tournament

#### Sambo (`sambo_levels`, federation)
FIAS sambo belt system

- **Beginner**: Breakfall forward on hands from a squat; Side breakfall rolling over the shoulder from a squat; Side breakfall with a rock from a squat; Back breakfall with a rock from a squat; Mount hold gripping arm and neck; Cross-body hold with hand grips; Side hold gripping arm and neck; Head hold gripping arm and neck; Hold from the legs embracing torso and arm; Turnover with hand grips from the side; Turnover with a lever; Unbalance by pulling a squatting partner; Unbalance by twisting or pushing a kneeling partner
- **Student Level 1**: Forward fall onto a bridge rolling from a squat; Forward fall on hands from standing; Side fall rolling over the shoulder from standing; Side and back falls with a rock from standing; Mount hold with outside leg grapevine; Cross-body hold gripping arm and hip; Side hold gripping torso and arm; Head hold embracing the torso; Throw with inside shin grip; Unbalancing by twisting and by pushing; Back trip (podnozhka) gripping arm and belt; Turnover gripping leg and arm; Elbow lever through the hip from side hold; Shoulder knot (uzel) from side hold
- **Student Level 2**: Forward fall on arms jumping from standing; Side fall rolling over partner's arm; Back fall jumping forward (half flip) and backward; Reverse cross-body hold gripping arm and hip; Side hold gripping both arms; Head hold gripping lapels under the arms kneeling; Inside ankle grip throw; Hip throw with a belt grip; Back reaping throw gripping arm and belt; Front trip gripping arm and belt; Turnover by pulling or pushing the jacket wing; Knee lever locking the hip with crossed legs; Elbow lever after a cross-body hold; Shoulder knot using the leg from side hold; Escapes from mount · side · head and leg holds
- **Student Level 3**: Leg-grip throw with a push; Outside shin-grip throw; Overhead (stomach) throw gripping neck and arm; Chest throw from seated gripping arm and torso; Back throw gripping the arm over the shoulder; Heel trip gripping one arm with both hands; Inside shin hook with a push; Outside reap gripping arm and belt; Turnover with belt grip and leg on the neck; Turnover with inside forearm grip; Reverse shoulder knot from side hold; Knee lever on opponent on hands and knees; Elbow lever on opponent lying on the chest; Achilles lock from seated; Self-defence: escapes from clothing and arm grips
- **Student Level 4**: Shoulder throw (through the back) both sides; Front sweep (podsechka) and side sweep in motion; Double-leg pickup throw; Combination: trip into hip throw; Counter-throw to a hip throw; Straight armlock from guard; Straight knee bar from top; Transitions hold to armlock in under 3 seconds; Grip fighting on the sambo jacket (kurtka); Knows sport sambo scoring and banned techniques
- **Student Level 5**: Sacrifice throws (sumi-style) with clean landing; Pickup throws over the chest; Flying armbar entry from standing; Ankle lock and knee lock chains; Escapes from leg locks; Three-throw combinations in randori; Total victory awareness (clean throw or submission); Competes in an official sambo tournament
- **Student Level 6**: Personal tokui-waza: 2 signature throws on both sides; Ground-to-submission chain of 3 techniques; Counter-throws to 3 common attacks; Tactical match plan by score and time; Demonstrates and explains all student-level techniques; Assists coaching beginners
- **Candidate for Master**: Full FIAS student syllabus demonstrated cleanly; National-level competition results; Referee rules knowledge exam; Teaches a full class under supervision
- **Master**: International-level competition or coaching record; Independent coaching of all student levels; Examines and grades students

### Gymnastics

#### Gymnastics levels 1-10 (`gymnastics_levels`, palee)
Generic numbered levels (add your own skills)

- **Level 1**
- **Level 2**
- **Level 3**
- **Level 4**
- **Level 5**
- **Level 6**
- **Level 7**
- **Level 8**
- **Level 9**
- **Level 10**

#### Women's artistic gymnastics levels (`artistic_women_levels`, federation)
USA Gymnastics Development Program levels 1-10

- **Level 1**: Forward roll and backward roll; Bridge held 5 seconds; Cartwheel; Beam: walks and releve turns; Bars: pullover with spot and front support; Vault: straight jump onto mats
- **Level 2**: Handstand held 2 seconds; Backward roll to push-up position; Bars: pullover and back hip circle; Beam: cartwheel to handstand practice on low beam; Vault: handstand flat-back onto mat stack
- **Level 3**: Round-off; Bridge kickover; Bars: squat-on and cast to horizontal; Beam: split leap and handstand; Vault: front handspring onto mats
- **Level 4**: Back walkover; Round-off back handspring; Bars: glide kip and cast to horizontal; Bars: long hang kip and back hip circle; Beam: cartwheel; Vault: front handspring over the table
- **Level 5**: Round-off back handspring back tuck; Front tuck or aerial; Bars: kip cast above horizontal and clear hip circle; Bars: flyaway dismount; Beam: back walkover or back handspring; Beam: back tuck dismount
- **Level 6**: Optional routines with required elements; Bars: cast to 45 degrees above horizontal; Back layout
- **Level 7**: Round-off back handspring layout; Bars: giant swing drills; Beam: acro series of two elements; Vault: handspring (Yamashita optional)
- **Level 8**: Full twisting layout; Bars: giant swings and release move drills; Beam: salto element; Vault: Tsukahara or round-off entry drills
- **Level 9**: Double twist or front layout full; Bars: release move; Beam: two-element acro series with a salto; Vault: Yurchenko layout
- **Level 10**: Floor: D and E value skills in routine; Bars: release and pirouetting elements; Beam: complete optional routine to Level 10 rules; Vault: Yurchenko full or harder

#### Xcel divisions (women's artistic) (`artistic_women_xcel`, federation)
USA Gymnastics Xcel Bronze to Sapphire

- **Bronze**: Cartwheel and handstand forward roll; Bars: pullover and back hip circle; Beam: leap and full turn on two feet; Vault: handstand flat-back
- **Silver**: Round-off and back walkover; Bars: kip or cast with clear hip; Beam: cartwheel or walkover; Vault: front handspring onto mats
- **Gold**: Round-off back handspring; Bars: kip cast and squat-on or circle; Beam: acro element and split leap 120 degrees; Vault: front handspring over the table
- **Platinum**: Back tuck in a pass; Every event meets the Platinum special requirements; Beam: acro series
- **Diamond**: Layout or twisting salto; Every event meets the Diamond special requirements; Beam: salto or two-flight series
- **Sapphire**: Harder value parts on every event; Age 12 or older

#### Men's artistic gymnastics levels (`artistic_men_levels`, federation)
USA Gymnastics men's Development Program

- **Level 1**: Forward and backward rolls; Pommel: front support hold 10 seconds; Rings: tuck hang and skin the cat; Parallel bars: support walk; High bar: hang and pullover
- **Level 2**: Handstand forward roll and cartwheel; Pommel: single leg circles on mushroom; Rings: muscle-up drills with support hold; High bar: cast and back hip circle
- **Level 3**: Round-off and back handspring with spot; Pommel: double leg circles on mushroom; Parallel bars: swing in support and straddle dismount; Vault: front handspring
- **Level 4**: Back tuck and front tuck; Rings: L-sit 2 seconds and swings; High bar: kip and underswing dismount
- **Level 5**: Pommel: circles on the pommel horse; Parallel bars: peach basket drills; High bar: giant swing drills
- **Level 6**: Layout and full twist on floor; Rings: back lever and support hold; High bar: giant swings
- **Level 7**: Pommel: flairs or scissors; Parallel bars: handstand and stutz; Vault: handspring front tuck
- **Level 8**: Floor: double salto drills; Rings: strength hold (cross or planche) drills; High bar: release move drills
- **Level 9**: Floor: double back; High bar: release move
- **Level 10**: Optional routines to the men's code; All six apparatus at competition level

#### Rhythmic gymnastics levels (`rhythmic_levels`, federation)
USA Gymnastics rhythmic levels 3-8 then FIG Junior and Senior

- **Level 3**: Age 6 or older; Releve walks and passe balance; Split leap and stag leap; Floor routine to music; One apparatus routine (rope or ball)
- **Level 4**: Pivot 360 degrees in passe; Arabesque and attitude balances; Group floor routine; Two apparatus routines
- **Level 5**: Age 7 or older; Floor and three apparatus routines; Hoop: rolls spins and tosses; Ball: throw and catch with one hand
- **Level 6**: Age 8 or older; Pivots of 720 degrees; Clubs: mills and small circles; Ring leap and cossack jump
- **Level 7**: Age 9 or older; Ribbon: spirals and snakes; Leg in hand balance (penche drills); Dynamic elements with rotation under a throw
- **Level 8**: Age 10 or older; Penche and ring balances; Apparatus masteries (risk elements)
- **Junior**: Age 13 or older (FIG junior); Routines with hoop ball clubs and ribbon; Fouette and illusion pivots
- **Senior**: Age 16 or older (FIG senior); Routines under the FIG Code of Points

#### Trampoline awards 1-15 (`trampoline_awards`, federation)
British Gymnastics trampoline proficiency awards

- **Award 1**: Waits their turn and behaves safely around the trampoline; Mounts and dismounts from the centre; Bounces lying sitting or on hands and knees
- **Award 2**: Seated bounce with arm movements; Bounces a set number of times and stops; Quarter turn upright; Seat drop without returning to feet; Star position
- **Award 3**: Straight jumps using the arms; Tuck jump; Astride jump and star jump; Half twist jump
- **Award 4**: Tuck jump touching below the knees; Straddle jump and split jump; Seat drop returning to feet; Two half twist jumps linked
- **Award 5**: Five straight jumps then stop for 3 seconds; Piked straddle jump; Front landing and back landing on a mat; Seat drop to feet with half twist; Routine: straddle seat to feet tuck half twist straight
- **Award 6**: Seat landing half twist to feet; Full twist jump; Front landing to feet; Pike jump; Ten-move routine with seat landings and twists
- **Award 7**: Swivel hips (seat half twist to seat); Back landing to feet; Hands and knees forward turnover to back landing; Seat landing to feet then front landing to feet
- **Award 8**: Seat landing to front landing to feet; Half twist to front landing and to back landing; Front and back landing with half twist to feet; Five back bounces
- **Award 9**: Piked and straight front and back landings; Front landing to back landing and back to front; Forward three-quarter turnover to back landing; Seat landing full twist to seat (roller)
- **Award 10**: Front or back somersault tucked; Back landing back pullover to feet; Front landing half turntable; Ten-move routine with one somersault
- **Award 11**: Front somersault piked; Back somersault tucked and back somersault straight or piked; Three-quarter front somersault straight to back landing; Routine with three somersaults; Floor conditioning: 20 crunches and 20 dorsal raises
- **Award 12**: Barani with straight legs; Crash dive straight; Back somersault tucked then front somersault piked; Routine with four somersaults including a barani
- **Award 13**: Barani tucked and piked; Back somersault then barani in the same shape; Crash dive to bounce roll; Routine with six somersaults
- **Award 14**: Barani straight; Back somersault with half twist; Full twisting front somersault; Crash dive to ball out; Routine with seven somersaults
- **Award 15**: Crash dive to ball-out barani; Full twisting back somersault straight; Rudi (front with one and a half twists); Cody from a front landing; Ten-somersault routine with tariff 5.6 or more

#### Tumbling levels (`tumbling_levels`, federation)
USA Gymnastics tumbling levels 1-10

- **Level 1**: Forward roll and backward roll; Cartwheel; Straight jump with stuck landing
- **Level 2**: Handstand forward roll; Round-off; Back roll to push-up
- **Level 3**: Round-off back handspring rebound; Front handspring
- **Level 4**: Round-off and two to four back handsprings
- **Level 5**: Round-off back handsprings back tuck; Passes of eight elements
- **Level 6**: Back pike or tuck finish; Whip back
- **Level 7**: Whip backs and back handsprings in series; Back layout
- **Level 8**: Back somersault with a full twist (360 degrees)
- **Level 9**: Back full in elements two to seven; No double somersault before the last element
- **Level 10**: A double somersault in the pass; Double back tucked or piked

#### Acrobatics levels (`acrobatics_levels`, palee)
Palee levels from acro gymnastics and hand balancing

- **Level 1**: Handstand against the wall 30 seconds; Bridge and splits; Base and flyer safety rules
- **Level 2**: Freestanding handstand 5 seconds; Pair balances: bird and throne; Cartwheel and round-off
- **Level 3**: Handstand 15 seconds and pirouette walk; Pair balances: shoulder stand and star; Back walkover
- **Level 4**: Press to handstand; Hand-to-hand drills with a spotter; Simple pair tempo element (toss to catch)
- **Level 5**: One-arm handstand drills; Balance routine of three elements; Tempo routine with a back salto toss
- **Level 6**: Hand-to-hand hold 3 seconds; Group pyramid of three; Combined routine to music

#### CrossFit gymnastics skills (`crossfit_gymnastics`, palee)
Palee skill progressions for CrossFit gymnastics

- **Foundations**: Hollow hold 30 seconds and arch hold 30 seconds; Dead hang 30 seconds; 10 push-ups to full depth; Box jump and step-down
- **Strict strength**: 5 strict pull-ups; 5 strict ring dips; 5 strict toes-to-bar or hanging knee raises; Wall walk to nose and wall
- **Kipping**: Kip swing 10 in a row; Kipping pull-ups 10 unbroken; Kipping toes-to-bar 10 unbroken; Handstand hold against the wall 30 seconds
- **Rx skills**: Chest-to-bar pull-ups 10 unbroken; Kipping handstand push-ups 5 unbroken; Double-unders 50 unbroken; Rope climb 4.5 metres with legs
- **Advanced**: Bar muscle-ups 5 unbroken; Ring muscle-up; Handstand walk 15 metres; Legless rope climb
- **Elite**: Ring muscle-ups 5 unbroken; Strict handstand push-ups 10 unbroken; Handstand walk over obstacles; Deficit handstand push-ups

#### Calisthenics levels (`calisthenics_levels`, palee)
Palee street workout strength progressions

- **Level 1**: 10 push-ups and 20 bodyweight squats; Dead hang 30 seconds and scapular pulls; Plank 60 seconds and hollow hold 30 seconds
- **Level 2**: 5 pull-ups; 10 dips on parallel bars; 20 push-ups; Tuck L-sit 10 seconds
- **Level 3**: 10 pull-ups and 20 dips; L-sit 10 seconds; Wall handstand 30 seconds; Tuck front lever 10 seconds; 5 pistol squats per leg (assisted allowed)
- **Level 4**: Muscle-up on the bar; Freestanding handstand 10 seconds; Advanced tuck front lever 10 seconds; Tuck planche 5 seconds; Human flag drills
- **Level 5**: 5 muscle-ups; Straddle front lever 5 seconds; Straddle planche drills; Human flag 5 seconds; Handstand push-up against the wall
- **Level 6**: Full front lever 5 seconds; Straddle planche 5 seconds; Freestanding handstand push-up; One-arm pull-up drills

#### Street workout freestyle (`street_workout_freestyle`, palee)
Palee freestyle bar progression

- **Level 1**: Front and back support on the bar; Swing with hollow and arch; Pullover
- **Level 2**: Muscle-up; Back hip circle; 180 degree switch grip in swing
- **Level 3**: Underswing dismount; Bar spin (360 degree spin over the bar); Kip-up on the bar
- **Level 4**: Giant swing with straps or spotter; 180 release and regrab; Combo of three dynamic elements
- **Level 5**: Unassisted giant swings; 360 release or flip dismount; Freestyle routine of 60 seconds

#### Parkour levels (`parkour_levels`, palee)
Palee technique tiers used by parkour schools

- **Level 1**: Safe landing and roll; Quadrupedal movement 20 metres; Safety vault and step vault; Balance walk on a rail
- **Level 2**: Precision jump to a line; Lazy vault and speed vault; Tic-tac off a wall; Cat hang (arm jump hold)
- **Level 3**: Kong vault; Cat leap from a standing jump; Wall run and climb-up; Precision jump of 2 metres
- **Level 4**: Dash vault and kash vault; Kong to precision; Running cat leap; Underbar
- **Level 5**: Double kong; Turn vault and laché; Flowing line of six movements
- **Level 6**: Long precision and running precision; Route planning and risk assessment; Coaches a beginner line

#### Freerunning levels (`freerunning_levels`, palee)
Palee acrobatic freerunning progression

- **Level 1**: Forward roll on hard ground; Cartwheel and round-off
- **Level 2**: Front flip on soft ground; Side flip drills (aerial)
- **Level 3**: Back flip; Wall flip (wall spin drills)
- **Level 4**: Webster; Gainer; Palm flip
- **Level 5**: Cork or double leg; Flip combinations on obstacles; Freestyle line with three flips

### Fitness

#### CrossFit levels (`crossfit_levels`, palee)
Palee levels from CrossFit scaling and benchmarks

- **Foundations**: Air squat to full depth with a neutral spine; Deadlift and press with PVC or empty bar; Hollow hold 30 seconds; Knows the class whiteboard and scaling
- **Scaled**: Front squat and push press with load; Ring rows and banded pull-ups; 2000 metre row under 10 minutes; Finishes Cindy scaled
- **Intermediate**: Power clean and power snatch with good form; 5 strict pull-ups and 10 push-ups unbroken; Single-unders 100 and double-under attempts; Back squat 1 times bodyweight
- **Rx**: Kipping pull-ups and toes-to-bar; Double-unders 30 unbroken; Fran and Grace at Rx loads; Back squat 1.5 times bodyweight (men) or 1.2 (women)
- **Rx+**: Bar and ring muscle-ups; Handstand push-ups and walks; Squat snatch and squat clean at Rx loads; Fran under 5 minutes
- **Competitor**: Open workouts at Rx with a top 25 percent finish; Deadlift 2 times bodyweight; Pacing plan for long chippers

#### Metcon engine levels (`metcon_levels`, palee)
Palee benchmarks for conditioning classes

- **Level 1**: Finishes a 12-minute AMRAP at a steady pace; 500 metre row under 2:30; Knows how to scale a movement
- **Level 2**: EMOM of 20 minutes without missing a minute; 1 km run under 5:30; 50 burpees under 5 minutes
- **Level 3**: 2000 metre row under 8:30; Holds pace over 30-minute chippers; Assault bike 50 calories under 4 minutes
- **Level 4**: 5 km run under 25 minutes; Intervals at threshold with even splits; 100 burpees under 9 minutes
- **Level 5**: 2000 metre row under 7:30; Murph or a 45-minute hero WOD; Plans and logs their own pacing

#### HYROX divisions (`hyrox_divisions`, federation)
HYROX race divisions (organiser's system)

- **Relay ready**: Runs 1 km four times with recovery; Each of the eight stations at Open load
- **Doubles**: Full simulation with a partner (split stations); Sled push and sled pull technique; 100 wall balls with partner swaps
- **Open**: 8 km of running with eight stations alone; 1000 metre SkiErg and 1000 metre row at steady pace; 80 metre burpee broad jumps; 100 metre sandbag lunges and 100 wall balls
- **Pro**: Full simulation at Pro loads; Compromised running at race pace; Race plan with target splits per station
- **Elite 15**: Qualifies at a Major or a regional championship; Season plan with peaking

#### Weightlifting classes (`weightlifting_classes`, federation)
Russian/EVSK sports classification (national tables)

- **Technique**: Snatch and clean with PVC from the hang; Overhead squat to full depth; Front squat with elbows high
- **Class III**: Full snatch and clean and jerk from the floor; Total meets the federation Class III standard; Knows competition rules and the three attempts
- **Class II**: Split or power jerk with a stable catch; Total meets the Class II standard
- **Class I**: Total meets the Class I standard; Competes in an official meet
- **Candidate Master of Sport**: Total meets the CMS standard at an official meet
- **Master of Sport**: Total meets the MS standard at a national meet
- **Master of Sport International Class**: Total meets the MSIC standard at an international meet

#### Powerlifting levels (`powerlifting_levels`, palee)
Palee strength standards (bodyweight multiples)

- **Beginner**: Squat deadlift and bench press to competition depth with empty bar; Bracing and the valsalva technique
- **Novice**: Squat 1 times bodyweight; Bench press 0.75 times bodyweight; Deadlift 1.25 times bodyweight
- **Intermediate**: Squat 1.5 times bodyweight; Bench press 1 times bodyweight; Deadlift 1.75 times bodyweight; Follows a periodised programme
- **Advanced**: Squat 2 times bodyweight; Bench press 1.35 times bodyweight; Deadlift 2.4 times bodyweight; Competes under IPF rules
- **Elite**: Squat 2.5 times bodyweight; Deadlift 3 times bodyweight; National-level total

#### Learn to swim stages (`swim_stages`, federation)
Swim England Learn to Swim stages 1-7

- **Stage 1**: Enters and exits the water safely; Moves forward 5 metres; Push and glide on the back from the wall; Names two pool rules
- **Stage 2**: Jumps in from the side; Floats on front and back; Swims 5 metres front and back
- **Stage 3**: Swims 10 metres without aids; Rotates from front to back; Submerges and picks up an object
- **Stage 4**: Push and glide underwater; Kicks 10 metres of each of the four strokes; Swims 10 metres continuously; Sculls head first on the back
- **Stage 5**: Treads water 30 seconds; 10 metres each of backstroke front crawl breaststroke and butterfly; Handstand in water held 3 seconds; Forward somersault in water
- **Stage 6**: 25 metres of one stroke; Swims 10 metres wearing clothes; Shouts and signals for rescue; Surface dive
- **Stage 7**: 25 metres each of front crawl backstroke breaststroke and butterfly; 50 metres without stopping; 100 metres using three strokes; Eggbeater tread for 30 seconds; Sitting dive; Obstacle course of four objects with feet off the floor

#### Ashtanga yoga series (`yoga_ashtanga`, federation)
Mysore-style series order (the school's system)

- **Sun salutations**: Surya Namaskara A and B with breath; Ujjayi breathing and drishti
- **Standing sequence**: Standing postures to Parsvottanasana; Closing sequence
- **Primary series half**: Seated postures to Navasana; Vinyasa between sides
- **Primary series**: Full Yoga Chikitsa to Setu Bandhasana; Marichyasana D bound; Supta Kurmasana
- **Intermediate series**: Backbends to Kapotasana; Leg-behind-head postures; Seven headstands
- **Advanced A**: Arm balances of Advanced A; Daily practice of six days a week

#### Strongman Levels (`strongman_levels`, palee)
Palee levels (strongman has no athlete ladder)

- **Foundations**: Barbell deadlift with neutral spine and full lockout; Back squat to depth with braced trunk; Strict overhead press with full lockout; Correct belt bracing (breath into belt) on heavy sets; Farmer's carry with handles: upright posture for 20 m; Sandbag lap and shoulder from the floor; Sled drag forward and backward; Safe dropping and bailing of implements; Chalk and tacky use and grip hygiene; Warm-up routine for hips · shoulders · grip
- **Implement Novice**: Log clean to rack in one continuous movement; Log push press and log jerk with locked finish; Axle continental clean to rack; Axle strict and push press; Atlas stone lap · stand-up and load to low platform; Yoke pick: braced set-up and short steps; Farmer's walk with pick · walk · controlled set-down; Tyre flip with chest drive and no bicep curl; Keg or sandbag carry over 20 m; Frame or front carry with stable trunk; Deadlift from 18-inch or with straps correctly set
- **Novice Competitor**: Log press for max reps in a timed window (contest format); Ref load u95 kg: log 70 kg reps from floor in 75 s; Ref load u95 kg: farmers 100 kg x 25 m under 60 s; Ref load u95 kg: yoke 200 kg x 25 m under 60 s; Stone series: load 3 stones of rising weight; Medley: carry plus drag transition without rest; Turn on yoke or farmers course where allowed; Deadlift for max reps in 60 s with full lockout each rep; Knows judging standards: lockout · down signal · line; Weigh-in · warm-up timing and attempt planning on contest day
- **Intermediate**: Circus dumbbell clean and press each arm; Viking press with lockout and controlled lowering; Atlas stone to shoulder-height platform; Stone over bar for reps; Keg toss or weight over bar with full hip drive; Hussafell or sandbag bear-hug carry for distance; Hercules or grip hold with braced shoulders; Power stairs or loading race with fast transitions; Truck or vehicle pull with harness and rope technique; Runs a peaking block for a contest
- **Advanced**: Log or axle press at contest-qualifying load for class; Full 5-stone series on time with no misses; Yoke and farmers at open-class loads with turn; Car or frame deadlift with straps; Medley of 3+ implements within time cap; Places in a regional or national qualifier; Manages weight class (cut or gain) safely; Coaches a novice through stone and log technique
- **Open Competitor**: Competes in open or national championship class; Completes all events of a full open contest; Event-specific weaknesses identified and programmed; Annual competition plan with peaks and deloads; Pro-level benchmark attempts logged (local→national tier)

#### Kettlebell Levels (`kettlebell_hardstyle`, palee)
Palee levels from StrongFirst standards

- **Foundations**: Hip hinge with dowel: three points of contact kept; Kettlebell deadlift with neutral spine; Goblet squat to depth with heels down; Plank with full-body tension 30 s; Hike pass to the rear with flat back; Two-hand swing: hip snap and vertical plank at top; Safe park of the bell after the last rep; Half get-up to tall sit each side; Suitcase and rack carry 20 m each side
- **Swing and Get-up**: One-arm swing x10 each side with crisp lockout of hips; Hand-to-hand swing switch without losing timing; Full Turkish get-up x1 each side with eyes on bell; Get-up high bridge and leg sweep correct; Breathing matched to swing (power breath at top); 10 sets of 10 two-hand swings with good form; Arm bar and windmill each side
- **Clean and Press**: Single clean to rack: no bell flop on forearm; Rack position: wrist neutral · elbow on hip; Strict press x5 each side with full lockout; Front squat from rack x5 each side; Clean and press ladder (1-2-3) with control; Bent-over and renegade row with square hips; Bottoms-up hold or press for shoulder control
- **Snatch**: High pull with hip drive and relaxed grip; Snatch x5 each side: punch through and no forearm bang; Snatch lockout held still before descent; Snatch descent without touching chest or shoulder; Hand care routine (callus management); Snatch intervals with heart-rate or rest control
- **Simple Standard**: 100 one-arm swings in 5 min (sets of 10); 10 get-ups in 10 min alternating sides; Simple bell: men 32 kg swing and get-up; Simple bell: women 24 kg swing · 16 kg get-up; Daily practice logged for 4+ weeks
- **SFG Standard**: Double-bell swing x10 to SFG standard; Double clean x5; Press x5 each side with SFG test bell; Double front squat x5; Snatch x5 each side and get-up x1 each side; Snatch test 100 reps in 5 min with category bell; Snatch test bell: women 12 or 16 kg · men 20/24/28 kg; No 'no count' reps: elbow and knees locked at top
- **Sinister**: Simple & Sinister session with Sinister bells; Sinister bell: men 48 kg swing and get-up; Sinister bell: women 32 kg swing · 24 kg get-up; Double-bell complex (clean · press · squat) planned and executed; Teaches the hinge and swing to a beginner

#### Kettlebell Sport Ranks (`kettlebell_sport_ranks`, federation)
Kettlebell sport ranks (IUKL and IKO)

- **Rank 3**: Competition bell rack: bell on chest · elbows on hips; Breathing pattern in rack and overhead; Jerk: half dip · bump · undersquat · fixation; Snatch: soft grip · one hand switch · fixation; Long cycle: clean · jerk · drop to rack · re-clean; Completes 10-min set without setting bell down; Reaches Rank 3 reps for own bodyweight class and bell; Knows no-rep rules (fixation · touching body · drop)
- **Rank 2**: Steady pace plan (reps per minute) held all 10 min; Grip and hand-care routine for snatch volume; Jerk lockout without press-out; Biathlon: jerk set then snatch set same day; Reaches Rank 2 reps for own class; Uses chalk only · no gloves or wraps
- **Rank 1**: Competes at amateur bell (men 24 kg · women 16 kg); Two-bell jerk or long cycle with stable rack rest; Reaches Rank 1 reps for own class; Periodised block towards a sanctioned meet; Has completed a sanctioned competition with judges
- **CMS (Candidate Master of Sport)**: Trains with professional bell (men 32 kg · women 24 kg); Reaches CMS reps in a sanctioned meet for own class; Clean pacing graph: last minute close to first; Efficient hand switch under 2 s in snatch; Travel and weigh-in routine for meets
- **MS (Master of Sport)**: Reaches MS reps at a sanctioned national or international meet; Mentors lower-rank lifters in technique
- **MSIC (Master of Sport International Class)**: Reaches MSIC reps at an international championship; Competes with professional bell in classic events

#### Running Levels (`running_levels`, palee)
Palee levels for recreational runners

- **Walk-Run Starter**: 5-min brisk walk warm-up and 5-min cool-down every session; Run 1 min / walk 90 s x8 (C25K week 1); Three sessions a week for 3 consecutive weeks; Conversational (talk test) easy pace; Upright posture · relaxed shoulders · soft landing; Correct running shoes and basic kit chosen; Knows RPE 1-10 and keeps runs easy
- **First 5K**: Run 20 min continuous (C25K week 5 run 3); Run 30 min continuous x3 in one week (C25K week 9); Completes a 5 km run or parkrun without walking; Dynamic warm-up: leg swings · skips · strides; Basic post-run stretching for calves · hamstrings · hips; Logs runs (time · distance · RPE)
- **5K Improver**: Four runs a week including one long easy run; Strides x6 after easy runs; Interval session (e.g. 400 m repeats) at controlled effort; Running drills: A-skip · B-skip · high knees · butt kicks; Runs a timed 5K and records a PB; Two strength sessions a week for runners (calf · glute · core); Even pacing: second half not slower than first
- **10K**: Long run of 60 min continuous; Tempo run at comfortably hard effort for 20 min; Hill repeats with good form uphill and downhill; Completes a 10 km race or timed run; Understands easy · tempo · interval training zones; Recovery habits: sleep · fuel · easy days easy
- **Half Marathon**: Follows a 12-week novice half plan (e.g. Higdon Novice 1); Long run progressively built to 10 miles (16 km); Practises race-day fuelling and hydration on long runs; Completes 21.1 km race; Taper week before race; Pacing strategy written and executed
- **Marathon**: Follows an 18-week novice marathon plan; Long runs built from 6 to 20 miles (32 km); Four run days plus one cross-training day weekly; Gels or carbs taken on schedule during 2h+ runs; Three-week taper completed; Completes 42.195 km marathon
- **Performance Runner**: Periodised season with base · build · peak · recovery; Threshold and VO2max sessions programmed weekly; Uses heart-rate or pace zones from a field test; Negative split in a goal race; Injury-prevention routine maintained all season

#### Road Cycling Levels (`road_cycling_levels`, palee)
Palee levels (the first three follow Bikeability)

- **Bike Handling**: Pre-ride bike check: brakes · tyres · chain · quick releases; Helmet and clothing fitted correctly; Start and stop under control from either pedal; Ride in a straight line one-handed while signalling; Look behind over shoulder without wobbling; Controlled braking: both brakes · weight back; Gear selection before hills and stops; Avoid a hazard with a swerve or emergency stop
- **Road Ready**: Start and finish an on-road journey safely; Primary and secondary riding position chosen correctly; Pass parked vehicles and side roads; Turn left and right at simple junctions; Communicate intentions with signals and eye contact; Fix a puncture and refit wheel
- **Confident Road Rider**: Ride complex junctions and roundabouts; Multi-lane roads and lane changes with planning; Plans and rides a route independently; Descends with braking before corners and correct line; Climbs seated and standing with cadence control; Eats and drinks while riding
- **Group Rider**: Holds a wheel at steady distance in a group; Rides two abreast and single-file on call; Uses group hand signals and calls (car back · hole · stopping); Through-and-off chain gang rotation; Smooth pace when on the front · no surges; Club ride of 2 h without being dropped
- **Endurance Rider**: Completes a 100 km ride or sportive; Fuelling plan per hour on long rides; Basic bike maintenance: chain clean · lube · brake pads; Bike fit checked: saddle height · reach · cleats; Rides in wind and rain with suitable kit
- **Performance Cyclist**: FTP field test (20-min) done and zones set; Structured intervals: sweet spot · threshold · VO2max; Cornering at speed with counter-steer and lean; Sprint out of the saddle and in the drops; Races or rides a timed event (TT · crit · gran fondo)

#### Indoor Cycling Levels (`indoor_cycling_levels`, palee)
Palee levels (programmes certify coaches only)

- **Bike Set-up**: Sets saddle height: slight knee bend at bottom of stroke; Sets saddle fore-aft and handlebar height; Clips in or straps feet securely; Uses resistance knob and emergency brake; Hand positions 1 · 2 · 3 known; Never spins with no resistance (always some load); Hydration and towel ready · knows when to sit and recover
- **Core Movements**: Seated flat with smooth round pedal stroke; Seated climb at lower cadence with added resistance; Standing climb with hips over pedals; Standing flat (run) with stable upper body; Jumps: smooth transitions seated to standing; Keeps cadence inside 60-110 rpm envelope; Completes a full 45-min class
- **Intensity Control**: Matches instructor RPE cues 1-10; Uses heart-rate zones from a monitor; Rides to the beat for cadence drills; Recovers HR between intervals before next effort; Sprint 20-30 s with resistance and safe deceleration
- **Power Rider**: Completes a 20-min FTP test on a power bike; Rides power zones on cue (watts or percent of FTP); Threshold block of 2x10 min held steady; Back-to-back classes or 60+ min ride
- **Class Leader**: Demonstrates every movement with correct form; Builds a class profile (warm-up · main set · cool-down); Sets up a new rider's bike correctly; Improves FTP between two tests

#### Rowing Levels (`rowing_levels`, palee)
Palee levels from British Rowing and Concept2 technique

- **Stroke Basics**: Foot straps set across widest part of foot; Loose hook grip with flat wrists; Tall posture: pivot from hips not lower back; Drive order legs · body · arms; Recovery order arms · body · legs; Catch: shins vertical · arms long · body forward; Finish: handle to lower ribs · slight lean back; Reads monitor: split /500 m · stroke rate · time; Sets damper and knows drag factor
- **Drills and Rhythm**: Pick drill: arms only → arms and body → full slide; Legs-only rowing with fixed upper body; Pause drills at finish and at body-over; Count rhythm: drive on 1 · recovery on 2-3-4; Holds constant split at a set stroke rate; Changes rate on command without losing length; Rows 20 min continuous steady state
- **Fitness Rower**: 30-min steady row at low rate; Interval sessions (e.g. 500 m repeats) with even splits; Completes 5000 m test; Uses heart-rate or RPE training zones; Logs results in a training log or Concept2 logbook
- **Test Ready**: Completes 2000 m test with a race plan (start · settle · sprint); Pacing within a narrow split range through middle 1000 m; Power strokes from frontstops for a fast start; Re-tests and improves 2k after a training block; Posts a result to Concept2 online ranking
- **Water Transition**: Capsize/swim test and water safety briefing passed; Carries and launches a boat with a crew; Squaring and feathering the blade; Blade placement at catch and clean extraction; Stops the boat and backs down on command
- **Advanced Rower**: Periodised plan with UT2 · UT1 · AT · race-pace work; Competes in an indoor rowing race or regatta; Coaches stroke sequence to a beginner; Long distance: 10 000 m or half-marathon row

#### Pilates Mat Levels (`pilates_mat_levels`, palee)
Palee levels from the classical mat order

- **Fundamentals**: Lateral (ribcage) breathing coordinated with movement; Finds neutral pelvis and imprint on demand; Powerhouse engagement without breath holding; Pelvic curl articulating bone by bone; Chest lift with neck long; Pilates stance and scapular stability; Dead bug or toe taps with stable pelvis
- **Basic Order**: The Hundred: 100 pumps with breath; Roll Up 3-5x without momentum; Single Leg Circles 3-5x each direction; Rolling Like a Ball 5-10x; Single Leg Stretch 5-10 sets; Double Leg Stretch 5-10x; Spine Stretch Forward 3-5x; Flows the 7 exercises in order with transitions
- **Intermediate Order**: Single and Double Straight Leg Stretch 5-10x; Criss Cross 5-10 sets; Open Leg Rocker 6x with balance; Corkscrew 3-5 sets; Saw 3-4 sets; Neck Roll 3 sets; Single Leg Kicks 5 sets; Double Leg Kicks 3 sets; Neck Pull 5x; Side Kick Series: front/back · up/down · small circles; Teaser 1 3x; Seal 6x; Full intermediate order with no rest between exercises
- **Advanced Order**: Roll Over 3 sets; Corkscrew with hips over 3-5 sets; Swan Dive 3-5x; High Scissors and High Bicycle 3-5 sets; Shoulder Bridge 3-5 kicks each leg; Spine Twist 3 sets; Jackknife 3x; Side Kicks advanced: bicycle · inner thigh · big scissors; Teaser 1 · 2 · 3 3x; Hip Circles 3 sets; Swimming 3 breaths; Leg Pull Front and Leg Pull Back 3 sets
- **Master Repertoire**: High Bridge 1x; Kneeling Side Kicks 4 sets; Mermaid 3 sets and Side Bend 3x each side; Snake/Twist 3 sets; Boomerang 3 sets; Crab 3-6x and Rocking 5x; Control Balance 3x; Push Ups 3-10x; Full Return to Life 34-exercise order in sequence; Flowing transitions with no breaks in the full order

#### Pilates Reformer Levels (`pilates_reformer_levels`, palee)
Palee levels from the classical Reformer order

- **Reformer Orientation**: Safe getting on and off the carriage; Changes springs · headrest and footbar safely; Neutral spine and breathing on the carriage; Footwork: toes · arches · heels · tendon stretch; Controls carriage return without banging
- **Basic Reformer**: The Hundred on the reformer; Frogs and leg circles in straps; Stomach Massage round back; Short Box: round back and flat back; Elephant with carriage control; Knee Stretches round and flat; Running and Pelvic Lift; Rowing into the sternum and 90 degrees; Basic order flowed with correct spring changes
- **Intermediate Reformer**: Coordination; Full Rowing series (1-6); Long Box: Pull Straps · T Pull · Backstroke; Long Box: Teaser and Breaststroke; Long Stretch series: Long · Down · Up Stretch; Long Back Stretch; Short Box: side to side · twist and reach · tree; Short Spine Massage; Semi Circle; Chest Expansion and Thigh Stretch; Knee Stretches knees off; Side Splits; Mermaid
- **Advanced Reformer**: Overhead; Swan on the footbar; Horseback and Hamstring Curls; Single Leg Elephant; Tendon Stretch and Single Leg Tendon Stretch; Side Sit Ups; Backbends and Arm Circles; Snake and Twist; Corkscrew and Tic Toc; Second Long Box: Grasshopper · Swimming · Rocking; Long Spine Massage; High Bridge; Front Splits
- **Master Reformer**: Headstands facing down and facing up; Headstands with straps; Control Balance Off; Control Balance Push Ups front and back; Star; Russian Splits; Russian Squat; Full classical reformer order in sequence

#### Mobility Levels (`mobility_levels`, palee)
Palee levels (no standard system)

- **Joint Health**: Daily CARs routine: neck · shoulders · spine · hips · ankles; Deep squat hold 60 s with heels down (assisted ok); Hip hinge toe-reach with straight knees; 90/90 hip switch without hands; Wall shoulder flexion: arms overhead with ribs down; Glute bridge hold 30 s; Cat-cow segmental spine control
- **Range Builder**: Couch stretch 60 s each side upright; Half split with front heel on block 30 s; Seated pike: hands reach past toes; Straddle sit upright with hands on floor in front; Table-top bridge with hips level; Thoracic rotation open book 10 each side; Ankle knee-to-wall test progression logged
- **Active Flexibility**: PAILs and RAILs in hip 90/90 paired; Active straight-leg raise held 5 s each side; Jefferson curl light with segmental control; Cossack squat to full depth each side; Head-on-floor bridge (crown) with control; Shoulder dislocates with band or dowel; Front split with hips on cushion or blocks
- **Intermediate Shapes**: Full bridge from floor with arms straight; Pike fold chest toward thighs with flat back; Pancake: elbows to floor in straddle; Front split within a hand-width of floor each side; Middle split hips at knee height or lower; Skin-the-cat or German hang shoulder extension; Pigeon pose upright with square hips
- **Advanced Shapes**: Full front split on floor both sides with square hips; Chest-to-floor pancake; Bridge with shoulders over wrists and straight legs; Wall walk-down to bridge and back up; Active pike compression: lift legs from floor in pike; Deep squat with arms overhead and upright torso
- **Elite Mobility**: Middle split on floor; Standing drop-back to bridge without wall; Stand up from bridge to standing; Oversplit or split with back-leg bend (needle prep); Maintains end-range strength routine 3x weekly

#### HIIT Levels (`hiit_levels`, palee)
Palee levels for interval training (no standard system)

- **Starter**: Completes 30 s work / 15 s rest intervals at RPE 4-6; Bodyweight squat to depth with heels down; Incline or knee push-up with straight body line; Step-back burpee without jump; Forearm plank 30 s; Reverse lunge with knee control; Knows RPE scale and when to scale down; Completes a full 30-min class with modifications
- **Foundations**: Equal work:rest intervals (e.g. 40:40) sustained; Full push-up x10 with chest to fist height; Full burpee with chest to floor x10; Jump squat with soft landing; Mountain climbers with hips level 30 s; Kettlebell or dumbbell swing with hip hinge; Bear crawl forward and back 10 m; Jumping jacks and high knees for 60 s
- **Intermediate**: Tabata 20:10 x8 with consistent reps; EMOM 10 min with planned reps; Jumping lunges with upright torso; Box or step jump with full hip extension and step down; Plank variations: shoulder taps and side plank 30 s; Shuttle sprints with sharp turns; Medicine-ball slams and throws; Partner drills (wheelbarrow · plank high-fives)
- **Advanced**: Work:rest of 2:1 or longer intervals at RPE 8-9; Burpee broad jumps or burpee box jumps; Plyometric push-up; Sled push or sprint intervals outdoors; AMRAP 20 min with steady pacing; Heart-rate recovery tracked between rounds; Bootcamp obstacle or partner carry course
- **Athlete**: Completes a benchmark HIIT test and re-tests to improve; Scales any session for self and a partner; Leads warm-up and demonstrates all standards; Balances HIIT with recovery days (max 2-3 hard/week)

#### Strength Training Levels (`strength_levels`, palee)
Palee levels from novice to advanced lifter

- **Movement Foundations**: Squat pattern: goblet squat to depth; Hinge pattern: Romanian deadlift with neutral spine; Push: push-up with straight body x10; Pull: inverted row or assisted pull-up; Lunge or split squat with knee tracking; Loaded carry with tall posture; Bracing: Valsalva breath before each rep; Warm-up sets ramp to working weight
- **Novice Lifter**: Barbell back squat below parallel; Bench press with arch · leg drive · bar touch chest; Standing overhead press with full lockout; Conventional deadlift from floor each rep reset; Power clean or barbell row technique; Linear progression: adds load each session for 8+ weeks; Sets safety pins or uses a spotter correctly; Logs every session (sets · reps · load)
- **Advanced Novice**: Heavy and light squat days within the week; Chin-up or pull-up strict x5; Deadlift 1.5x bodyweight (Dan John 'expected' ref); Manages a stall with a reset or deload; Uses RPE or reps in reserve on top sets; Belt and lifting shoes used appropriately
- **Intermediate Lifter**: Weekly progression programme (e.g. Texas Method or 5/3/1); Volume · intensity and recovery days structured in the week; Accessory work chosen for weak points; Tests a 1RM or rep max safely with spotters; Front squat and pause variations; Bodyweight bench press for reps
- **Advanced Lifter**: Block or monthly periodisation planned; Deadlift 2x bodyweight (Dan John 'game changer' ref); Pull-ups x15 strict (Dan John 'game changer' ref); Bodyweight squat x15 (Dan John 'game changer' ref); Autoregulates load from daily readiness; Coaches a novice through the main lifts

### Dance

#### Ballet graded levels (RAD structure) (`ballet_rad_graded`, federation)
RAD graded structure (not affiliated)

- **Pre-Primary**: Posture and parallel feet; Pointing and flexing feet; Skips and galops to music; Free movement to a story
- **Primary**: First position and demi-plie; Transfer of weight and balance on demi-pointe; Sautes in first position; Curtsey or bow and a dance
- **Grade 1**: Plies in first and second; Battements tendus; Port de bras first to fifth; Character dance
- **Grade 2**: Glissés and retirés; Changements and echappes sautes; Polka and spring points
- **Grade 3**: Pirouette preparations and quarter turns; Petit allegro with assembles; Grand battement
- **Grade 4**: Single pirouette en dehors; Glissade and jeté combinations; Adage with developpes
- **Grade 5**: Pirouettes en dedans; Grand jeté and sissonne; Free movement section
- **Grade 6**: Fouette preparations and double pirouette drills; Batterie (entrechat quatre); Character and free movement dances
- **Grade 7**: Grand allegro sequences; Advanced adage with balances
- **Grade 8**: Solo performance with artistry; Music and style interpretation across eras

#### Ballet vocational levels (RAD structure) (`ballet_rad_vocational`, federation)
RAD vocational structure (not affiliated)

- **Intermediate Foundation**: Barre and centre at vocational standard; Pointe work introduction; Double pirouette en dehors
- **Intermediate**: Pointe enchaînements; Fouetté rond de jambe en tournant; Grand allegro with tours en l'air (male)
- **Advanced Foundation**: Multiple pirouettes and fouettés; Batterie with entrechat six
- **Advanced 1**: Classical solo variation; Sustained adage on pointe
- **Advanced 2**: Professional-level class; Two solo variations
- **Solo Seal**: Solo Seal variations and own solo

#### Contemporary dance grades (`contemporary_grades`, palee)
Palee grades (the ISTD has no graded contemporary exams)

- **Grade 1**: Parallel and turned-out positions; Spinal curves and contractions; Floor rolls and weight transfer
- **Grade 2**: Swings and suspensions; Falls and recovery; Travelling phrase with direction changes
- **Grade 3**: Spirals and tilts; Inversions with safe weight bearing; Improvised task
- **Grade 4**: Release technique phrases; Jumps with spine articulation; Partner contact basics
- **Grade 5**: Floor work sequences; Contact improvisation lifts; Own short choreography
- **Grade 6**: Performance of a set solo; Choreography with a clear intention

#### Latin American medal levels (`latin_medals`, federation)
Medal tests like the ISTD and IDTA (not affiliated)

- **Social**: Cha cha and rumba basic movement; Leading and following in closed hold
- **Bronze**: Chosen dances from cha cha samba rumba paso doble and jive; Bronze figures with timing; Hip action (Cuban motion)
- **Silver**: Silver figures in the chosen dances; Spins and turns with spotting
- **Gold**: Gold figures in the chosen dances; Musicality and floorcraft
- **Gold Star**: Gold Star awards in the chosen dances; Competition-ready routines

#### Salsa levels (`salsa_levels`, palee)
Palee levels (common school progression)

- **Beginner 1**: Basic step on1 or on2 in time; Side basic and back basic; Right turn for the follower; Cross-body lead
- **Beginner 2**: Left turn and inside turn; Open and closed hold changes; Hears the clave and the one
- **Improver**: Cross-body lead variations; Copa and hammerlock; Basic shines
- **Intermediate**: Double turns with spotting; Hand-change combinations; Styling for leaders and followers
- **Advanced**: Multiple spins and turn patterns; Shines in partnerwork; Musical breaks and accents
- **Performance**: Team choreography; Lifts and dips with safe technique

#### Bachata levels (`bachata_levels`, palee)
Palee levels (sensual and Dominican styles)

- **Beginner 1**: Basic step with the tap on 4 and 8; Side and box basics; Closed and open hold
- **Beginner 2**: Right and left turns; Hip motion in time; Leading through the frame
- **Improver**: Body rolls and waves (sensual); Dominican footwork; Turn combinations
- **Intermediate**: Head rolls and hair whips with neck safety; Musicality: breaks and the derecho; Connection in close embrace
- **Advanced**: Counter-body movements and isolations; Dips and drops with safe technique; Social leading of complex patterns

#### Hip-hop levels (`hiphop_levels`, federation)
ISTD street dance medals plus a Palee starter level

- **Starter**: Bounce and rock grooves; Two-step and side step; On-beat counting in eights
- **Bronze**: Running man and Roger Rabbit; Party dances: Bart Simpson and Cabbage Patch; 32-count routine
- **Silver**: Isolations: chest head and arms; Footwork: kick ball change and heel-toe; Freestyle 30 seconds in a circle
- **Gold**: Texture changes (hit glide and flow); Choreography with formations; Freestyle battle round

#### Commercial and R&B levels (`commercial_rnb_levels`, palee)
Palee levels for commercial dance classes

- **Level 1**: Grooves in R&B tempo; Body rolls and isolations; Learns an 8-count phrase quickly
- **Level 2**: Floor transitions and knee spins; Facials and performance to camera; 64-count choreography
- **Level 3**: Speed changes and accents on lyrics; Turns and jumps within choreography
- **Level 4**: Music video style piece; Own choreography for a short track

#### Breaking levels (`breaking_levels`, palee)
Palee levels from WDSF breaking elements

- **Level 1**: Toprock: Indian step and two-step; Six-step; Baby freeze
- **Level 2**: Three-step and CC footwork; Chair freeze; Go-down transitions
- **Level 3**: Backspin and turtle drills; Headstand freeze; Combo of toprock footwork and freeze
- **Level 4**: Windmill; Air baby and hollowback drills; One-minute set in a cypher
- **Level 5**: Flares or headspins; Power move combos; Battle rounds with musicality

#### Reggaeton levels (`reggaeton_levels`, palee)
Palee levels (urban Latin)

- **Level 1**: Dembow rhythm in the feet; Basic perreo step with safe posture; Hip circles
- **Level 2**: Isolations of hips and chest; Travelling steps and turns; 32-count routine
- **Level 3**: Floor work and level changes; Accents on the snare; Freestyle 30 seconds
- **Level 4**: Performance choreography with styling; Partner reggaeton basics

#### Heels levels (`heels_levels`, palee)
Palee levels for heels classes

- **Level 1**: Walks and turns in heels with ankle control; Posture and hip sway; Hair flicks with neck safety
- **Level 2**: Floor work: kneeling transitions; Leg lines and extensions; 32-count choreography
- **Level 3**: Floor spins and slides; Chair work basics; Performance with facials
- **Level 4**: Drops and splits in heels (when flexible enough); Own short choreography

#### Pole levels (`pole_levels`, palee)
Palee levels from common studio grading

- **Level 1**: Walks and pivots around the pole; Fireman spin and back hook spin; Chair spin; Basic climb and sit
- **Level 2**: Pole sit hands-free; Crucifix; Spin combinations on static and spinning pole; Inverted crunch drills
- **Level 3**: Basic invert from the floor; Outside leg hang and inside leg hang; Butterfly
- **Level 4**: Aerial invert; Shoulder mount from the floor; Gemini and cupid
- **Level 5**: Ayesha (elbow grip); Deadlift shoulder mount; Iron X drills
- **Level 6**: Handspring (twisted grip); Flags and drops with control; Routine of 2 minutes on both sides

#### Aerial silks levels (`aerial_silks_levels`, palee)
Palee levels from circus school progression

- **Level 1**: Single foot lock from the ground; Basic climb (Russian or French); Invert in the knot
- **Level 2**: Double foot locks in the air; Hip key; Straddle back inversion; Scorpion and diaper wrap
- **Level 3**: Inverted climb; Single star drop; Sequence of three poses
- **Level 4**: Wheel-downs; Salto drop; Belay and Russian climbs mixed
- **Level 5**: Double star drop; Aerial routine of 2 minutes

#### Aerial hoop levels (`aerial_hoop_levels`, palee)
Palee levels from circus school progression

- **Level 1**: Hip-hang and seated mount from the ground; Bird's nest under the bar; Pike beat mount drills
- **Level 2**: Pike beat mount; Mermaid and man in the moon; Spinning poses
- **Level 3**: Front balance and back balance; Gazelle; Straddle mount
- **Level 4**: Angel and top-bar standing; Ankle hang
- **Level 5**: Rolls and drops with control; Routine of 2 minutes

#### Tap dance (`tap_grades`, federation)
ISTD tap structure (not affiliated)

- **Pre-Primary**: Bounce in time to music; Step and jump with clear sounds; Ball taps and ball beats; Toe taps; Heel beats; Step ball change; Gallops across the room; Step clap stamp clap pattern; Keeps a steady beat when clapping; Performs a short teacher-led tap routine
- **Primary**: All Pre-Primary steps clean and in time; Ball change; Single paradiddle (paddle); Preparation for shuffles (forward and back brush); Ball and heel beats sequence; Skips and travelling steps to music; Claps a simple given rhythm; Performs a short dance with a partner or group
- **Grade 1**: Tap step and heel tap; Ball dig and heel dig; Spring; Forward shuffle; Standard flap and flaps to the toe; Basic crawl and sideways crawl (feet together); Pick up step; Tap step ball change; Shuffle ball change; Rag style: step heel beat; Jazz style: pick up steps; Boogie style: tap step heels and tap step ball change; Swing style: shuffle ball changes; Blues style: ball changes; Performs a solo dance up to 45 seconds
- **Grade 2**: Stomp and drop; Side shuffle and shuffles round the side; 4 beat cramp roll; Pick ups on 2 feet; Pick up spring and pick up hop; Shuffle hop step; 4 beat riff; Separated crawl sideways; Double paradiddle (paddle); Single time step; Travelling pick ups (Celtic style); Turning step on the diagonal both sides
- **Grade 3**: Toe flam; Back shuffle; 5 beat cramp roll; 3 beat riff forward and 5 beat riff; Pick up on 1 foot (with preparation); Pick up change and pick up ball change; Shuffle spring; Basic waltz step single and double; Double time step; Paddles exercise; Unseen sequence of 2 known steps set by teacher
- **Grade 4**: Double shuffle; Flap to toe sideways; 3 beat riff forwards and backwards; 3 beat ripple; Shuffle pick up change; Pull back (on two feet); Bufalino crawl and close work crawl; Riffs and cramp rolls in 3/4; Triple time steps; Claps 16th notes and improvises footwork; Turning step both sides
- **Grade 5**: 3 beat paddle; Double shuffle to the side; Flam; 4 beat ripple; Round the sides; 3 beat and 4 beat wing preparation; Maxi Ford with toe tap; Sugars; Pick up time steps single double and triple; Shuffle time step solo; Basic Shim Sham; Optional: double wings and toe beat crawl
- **Grade 6**: 4 beat progressive tap; Criss cross shuffle; Progressive shuffle; 4 beat cramp roll change; Double scuffle and twist scuffle; 5 beat open riff; Wing preparations in sequence; Single · double · triple shuffle time steps with breaks and half breaks; Time steps starting on 8 or on 1; Solo dance of own style choice
- **Intermediate**: Slap · splat · snatch and slam; 3 beat shuffles · flaps and pull backs; Drum cramp roll and 6 beat cramp roll; Inside flam and outside flam; Suzie Q; Maxi Ford with step; Cahito; Compass turn and rhythm turn with shuffle; Shuffle off to Buffalo; 5 beat paddle; 6 beat and 7 beat riffs; 11 beat criss cross riff; Ripple down; Rhythm · travelling and wing-preparation time steps; Cross accent and light and shade exercises; Theatre tap and commercial tap sequences; Own dance composition up to 2 minutes
- **Advanced 1**: Progressive taps; Roll time steps; 12 beat criss cross riffs; Closed pull backs; 2 bar single · double and triple wing preparation time steps; Turning step with Maxi Ford; Suzie Q technical exercise; Examiner-set time steps with syncopation and tacet; Improvises a 2 bar 4/4 rhythm with 16ths; Blues and quick jazz sequences; Optional: mixed Maxi Ford · wing on one foot · wing change
- **Advanced 2**: Single · double · triple and double-triple cramp roll time steps; 4 beat press cramp roll; Syncopated shuffle pick up change; Open and closed pull backs; Eddie's riff and Eddie's travel; Rattle: basic · progressive and double toe; Back travel and side travel; Wings or ripples turning; Spanish waltz amalgamation; Free improvisation to examiner's music; Optional: pendulum wings

#### Jazz dance (`jazz_grades`, federation)
ISTD Modern Theatre structure (not affiliated)

- **Primary**: Natural walks on the diagonal in time; Limbering: magic feet · leg stretching · squeeze and stretch; Running in a circle with control; Claps and marks a simple rhythm (1234&5); Skipping and galloping patterns; Bounces together with the group; Running with action (arms and focus); Performs a 45-second character dance
- **Grade 1**: Set warm-up from memory; Side stretch and forward stretch; Foot exercise: point and flex; Abdominal strengthening exercise; Front kicks with straight legs; Tendus in parallel; Jazz walks in a circle; Step ball change; Split runs; Basic turn on the spot; Claps and marks a 2-bar free rhythm; Solo dance of 16 bars
- **Grade 2**: Limbering sequence with spine roll-downs; Front kicks to 90° with control; Simple head and shoulder isolations; Jazz walks with arm lines; Step ball change travelling; Jazz pas de bourrée on the spot; Chassé travelling; Step turn at low level; Sautés in parallel; Set rhythm 1&2 3&4 clapped and danced; Set amalgamation from memory
- **Grade 3**: Side stretch option A or B; Leg stretching with front kicks; Side kicks exercise; Head · shoulder · ribcage and hip isolations; Triple runs; Jazz pas de bourrée travelling; Split jump; Step and front kick; Front and side step ball change; Step turn at high and low level; Front and side flick kicks; Claps and marks free rhythm with half and quarter notes
- **Grade 4**: Forward and side stretch with spine loosening; Front and side kicks set exercise; Hip loosening or push-aways exercise; Body strengthening floor sequence; Set isolation exercise; Free rhythm with 12th notes and missed beats; Single turns both sides; Kicks set exercise both sides; Split runs travelling; Two combination steps danced consecutively; Solo dance of 1 to 1½ minutes
- **Grade 5**: Isolations seen individually; Improvisation to unseen music; Drag runs forwards and sideways; Step and sideways split run; Step and forward split run; Circular spring without body line; Accented hop; Step and coupé turn with extended leg; Turns option A or B both sides; Unset sequence given by the teacher; Jazz · musical theatre or lyrical amalgamation
- **Grade 6**: Limbering set exercise with full range; Jazz arm exercise; Step and retiré with body line and fondu; Tilts; Extended spring sideways; Accented hop with varying leg line; Accented hop with half turn; Forward leap; Kicks option A or B; Dance vocabulary sequence with 4-count improvisation; Lyrical · musical theatre or jazz amalgamation
- **Intermediate Foundation**: Circular walk and triple run; Drag run; Jazz change of weight; Jazz pas de bourrée travelling · turning and on the spot; Drag turns front and back; Jazz pirouette at low level; Twist turn and swivel turn; Travelling jump with turn; Front kick with bent or straight supporting leg; Extended spring sideways and accented hops; Circular spring and forward leap; Isolations and set rhythm clapping
- **Intermediate**: Barre work: figure of 8 leg swings; Développé walk with lay back; Trudging · cushion and circular walks; Jazz pas de bourrée turning; Single pirouettes outwards and inwards at low and high level; Front and back twist turns · spin · open turns; Front · side and round kicks; Side kick with tilt; Forward leap with développé; Extended tuck jump; Step and spring turn with picked-up leg; Split · picked-up and turning ball changes; Leaps on the diagonal and elevated turns; Interprets free rhythm with syncopation
- **Advanced 1**: Jazz adage set exercise; Falls: knee drop and back fall; Triple walk and walks set exercise; Double pirouettes at low and high level; Barrel turn (single or more); Single turn with leg in attitude; Multiple pirouettes in 2nd with fouetté action; Kicks with hip extension front and side; Round kicks outward and inward; Développé side leap and stag leap; Leap turn with varying leg lines; Accented hops with a whole turn; Improvises immediately to examiner's free amalgamation
- **Advanced 2**: Technical floor sequence; Falls and tilts set exercise; Extended walks with body tilt; Double or more pirouettes in parallel or turned out; Spin turns (chaînés) at various levels; Barrel turns with bent or straight legs; Double tour en l'air; Kicks with layout or back bend; Attitude leaps and scissor hop; Jazz sissonne and straddle jump; Turns on the diagonal set exercise; Two contrasting set amalgamations (e.g. blues); Own solo of 1½ minutes

#### Ballet (Cecchetti method) (`ballet_cecchetti`, federation)
ISTD Cecchetti structure (not affiliated)

- **Pre-Primary**: Demi-pliés in 1st position; Walking on tip toes; Flexing and pointing the feet; Point and close; Curling and stretching the body; Hand movements to music; Jumps in 1st position; Responds to music in imaginative scenes; Curtsey or bow
- **Primary**: Skips into the room to music; Demi-pliés and rises; Battement tendu; Foot stretching and marching; Hand exercises · arm lifting · arm sways; Sautés; Galops sideways and pony canters forwards; Échappés sautés; Preparatory polka with spring points; Improvises to unheard music; Expressive solo up to 45 seconds
- **Grade 1**: Knows points of the room corners 1-4; Knows 1st · 2nd and 3rd positions of the feet; Barre: demi-pliés in 2nd and 1st; Battements tendus à la seconde facing the barre; Grands battements devant sideways to the barre; Rises combined with running on the toes; Port de bras in the centre; Retirés and exercise for 3rd arabesque; Quarter turns with use of the head; Échappé sauté from 1st with sautés; Simple sideways polka with spring points; Posé temps levé and galops; Classical or demi-caractère solo up to 45 seconds; Révérence
- **Grade 2**: Works in 3rd position of the feet; Knows 4th and 5th positions and arm positions 2nd · 5th en bas/avant/haut; Rise and demi-pliés in 2nd · 1st and 3rd; Battements tendus en croix; Grands battements devant and à la seconde; Ronds de jambe à terre; Échappés relevés; Retiré passé; Preparatory exercise for tour en l'air (head use); Pas de chat with changements; Petits jetés devant or derrière; Balletic polka forwards and sideways; Unseen enchaînement with échappés and changements
- **Grade 3**: Works in 5th position of the feet; Knows directions of the body and terms plier and sauter; Battements dégagés from 1st; Grands battements derrière facing the barre; Battements frappés; Retirés and développés; Fouetté à terre into arabesque; Développé and temps lié in the centre; 1st and 3rd arabesques; Relevés with bourrée en tournant; Preparation for pirouette en dehors; Assemblés dessus and dessous soutenu; Pas de bourrée dessous soutenu and de suite; Jetés temps levés with coupés; Balancés sideways
- **Grade 4**: Knows five positions of the head and arabesques 1-3; Full pliés in 2nd · 1st and 5th; Single and double battements frappés; Fondu movements; Développé and demi-rond de jambe; Relevés devant · derrière and passé; Adage with 1st · 2nd and 3rd arabesques both sides; Single relevé pirouette en dehors; Glissades devant and derrière soutenu; Sissonnes en avant fermées; Temps levé chassé pas de bourrée; Coupé chassé temps levé round the room; Soutenu turns en dedans on the diagonal; Batterie: échappé sauté closing with a beat; Classical solo up to one minute
- **Grade 5**: Petits battements at the barre; Développé with grand rond de jambe en l'air; Battements balancés; Grand plié · développé and demi-rond in the centre; 4th and 5th arabesques; Pirouette en dehors and pirouette en dedans; Changements and soubresauts; Glissade assemblé; Sissonne en avant ouverte and en arrière fermée; Entrechat quatre; Jeté en attitude devant round the room; Balancé en tournant; Petits tours on the diagonal both sides; Unseen enchaînement of up to 3 steps
- **Grade 6**: Knows effacée · attitudes and five movements of the foot; Battements dégagés with piqués; Grands battements and frappés en croix; Deux grands ronds de jambe en l'air avec arabesque; Attitudes with pirouette en dedans; Pirouette en dehors from 4th position; Échappés sautés with pas de bourrée dessous; Pas de bourrée couru; Demi-contretemps and assemblé élancé on the diagonal; Grands jetés en tournant; Posé tours and petits tours on the diagonal; Entrechat royale and entrechat trois; Unseen enchaînement of up to 4 steps
- **Intermediate Foundation**: Theory: positions · seven movements · eight directions · five arabesques; Uses the eight fixed points of the room; Full traditional barre from pliés to relevés; Adage with attitude and grand rond de jambe en l'air; Pirouettes en dedans and en dehors from 4th; Brisé dessus soutenu; Entrechat trois derrière and devant; Glissade jeté and jeté temps levé; Grands jetés en tournant both sides; Posé tours en dedans or petits tours on the diagonal; Pointe (girls): flexing · rises · échappés relevés; Boys option: grands changements and échappés battus; Classical solo up to one minute (not on pointe)
- **Intermediate**: Theory of port de bras and correct movements of the foot; Ronds de jambe en l'air and fouettés à terre; Grand fouetté and développé en tournant; Preparation for fouettés rond de jambe en tournant; Grande préparation and pirouettes en dehors from 4th; Pirouettes en dedans from a lunge and from 4th; Ballonné simple and écarté; Échappé battu beating out and in; Pas de bourrée en tournant en dehors and en dedans; Entrechat quatre and royale combinations; Cabriole devant ouverte; Grand jeté en tournant to posé in 2nd arabesque; Petits pas de basque en tournant; Pointe: pas de bourrée piqués · couru · posés coupés and emboîtés; Boys: tour en l'air from changement and from relevé
- **Advanced 1**: Traditional and additional barre including battements jetés at 45°; Adage study and jetés of adage; Arabesque penchée; Promenades in arabesque · attitude and 2nd; Cinq relevés · pas de chaconne · temps de courante; Pirouettes en dedans in attitude or arabesque; Pirouettes en dehors with extension en l'air; Fouettés rond de jambe en tournant; Entrechat cinq and brisé dessous; Cabriole derrière and jeté battu à la seconde; Sissonnes battues and temps de cuisse; Ballonné à trois temps; Pointe: soutenu turns · posé tours · posé développé; Boys: double tour en l'air and tours à la seconde
- **Advanced 2**: Full traditional barre with option A or B additions; Battements tendus with dégagé en tournant; Advanced adages from the Cecchetti days of the week; Grands jetés en attitude and à la seconde; Entrechat six and entrechat six de côté; Assemblé Cecchetti; Jeté double rond de jambe sauté en avant and en arrière; Sissonnes retombées with entrechat six; Jeté fouetté sauté en tournant; Coupé jeté en tournant round the room; Douze jetés en tournant and petits tours both sides; Pointe: advanced enchaînements on softened blocked shoes; Classical solo (tutu optional)

#### Ballet (Vaganova method) (`ballet_vaganova`, federation)
Vaganova 8-year programme (yearly content reconstructed)

- **Year 1**: Five positions of the feet and preparatory arm position; Demi-plié and grand plié facing the barre; Battement tendu and tendu jeté; Rond de jambe par terre en dehors and en dedans; Sur le cou-de-pied positions; Battement frappé and battement fondu (basic); Relevé on demi-pointe in 1st · 2nd and 5th; Grand battement jeté; Port de bras 1st and 2nd; Épaulement croisé and effacé introduced; Temps lié par terre; Sauté in 1st · 2nd and 5th; Changement de pieds and échappé sauté; Pointe (girls): relevés in 1st and 2nd facing the barre
- **Year 2**: Barre exercises sideways to the barre en croix; Rond de jambe en l'air; Petit battement sur le cou-de-pied; Battement développé to 90°; Double frappé; Port de bras 3rd; Small poses croisée · effacée · écartée; 1st to 4th arabesques; Preparation for pirouettes (quarter and half turns); Assemblé and glissade; Sissonne simple and sissonne fermée; Pas de chat and jeté; Pas de bourrée with change of feet; Pointe: échappé · pas de bourrée suivi in the centre
- **Year 3**: Grand rond de jambe jeté; Flic-flac; Battement développé in big poses; Port de bras 4th; Single pirouette en dehors and en dedans from 5th and 2nd; Pas de basque; Sissonne ouverte at 45°; Entrechat quatre · royale and trois; Grand changement de pieds; Pas de chat and petit jeté combinations; Pas couru; Pointe: tours chaînés and pas de bourrée en tournant
- **Year 4**: Pirouette from 4th en dehors and en dedans; Double pirouettes from 5th; Preparation for tours in big poses; Fouetté at 45°; Renversé (preparatory); Entrechat cinq; Brisé; Cabriole at 45°; Grand jeté in 1st arabesque; Sissonne tombée; Pointe: tours piqués and beaten steps on pointe
- **Year 5**: Tours in big poses (attitude and arabesque); Double tours from 4th; Tours chaînés on demi-pointe and pointe; Grand fouetté (adagio); Jeté entrelacé; Saut de basque; Cabriole at 90°; Entrechat six; Grand assemblé en tournant; Boys: single tour en l'air; Pointe: tours from 5th and from 4th
- **Year 6**: Renversé en dehors and en dedans; Grand fouetté en tournant; Double tours in big poses; Fouettés en tournant (8-16); Grand sissonne renversée; Double assemblé (boys); Boys: double tour en l'air; Jeté en tournant in series; Pointe: tours in big poses on pointe; Duet class basics (supported pirouettes)
- **Year 7**: Multiple pirouettes (3+) en dehors and en dedans; 32 fouettés en tournant (girls); Grandes pirouettes à la seconde (boys); Entrechat huit and brisé dessus-dessous; Revoltade and double cabriole (boys); Grand allegro combinations across the floor; Pas de deux: lifts and supported adagio; Character and historical dance styles; Classical variation from repertoire
- **Year 8**: Full virtuoso class at professional tempo; Multiple tours in big poses and fouettés with doubles; Manège of piqués or jetés en tournant; Coda-level grand allegro; Pas de deux with full lifts and fish dives; Two repertoire variations performed; Final state examination class; Stage performance in a full ballet

#### Kizomba (`kizomba_levels`, palee)
Palee levels (no examining body)

- **Level 1 · Foundations**: Finds the main beat in kizomba music; Closed embrace (abraço) with relaxed frame; Weight transfer on every step; Musical walk forward and back; Basic step (passo básico) in place; Side step (passo lateral); Basic step forward and back; Leader's exit (saída) to the side; Lead and follow through the chest; Pause and restart on the beat
- **Level 2 · Improver**: Saída da dama (follower's exit); Retrocesso (backward walk of the follower); Vírgula; 3x3 (three-by-three) pattern; Balance (balanço) in place; Basic pivots in closed hold; Simple follower turn and return to embrace; Corridinha (small running steps); Navigation on a social floor without collisions; Dances a full song without losing the beat
- **Level 3 · Intermediate**: Cruzado (cross step) for leader and follower; Around the world; Foot swipe (rasteira); Opening to open hold and closing again; Double-time steps (contratempo) on the leader cue; Linked combinations of 4+ figures; Follower hip and body styling (ginga); Leader body isolation to signal changes; Musicality: stops and breaks in the song; Dances with partners of different levels
- **Level 4 · Advanced**: Kota and semba-rooted steps; Multiple follower turns with clean finish; Shadow position walks and exits; Tarraxinha slow isolations; Urban kiz basics: lines and freezes; Improvises fully led sequences; Interprets melody and percussion layers; Leads or follows both roles at basic level; Smooth recovery from mis-leads
- **Level 5 · Master**: Signature style with own variations; Semba · kizomba · urban kiz switching in one song; Dynamic contrast: slow motion and fast footwork; Choreographed couple routine of 2+ minutes; Assists teaching a beginner class; Gives clear connection feedback to partners

#### Zumba / dance fitness (`dance_fitness_levels`, palee)
Palee levels for dance fitness classes

- **Starter**: Follows the instructor's visual cues; Merengue march and side-to-side step; Salsa basic step forward and back; Cumbia tap step with arm sway; Reggaeton tap and lean step; Low-impact options for each move; Completes 30 minutes of class; Hydration and self-monitoring of intensity
- **Core Rhythms**: Merengue with arms and travelling; Salsa side basic and cross-body styling; Cumbia with turns; Reggaeton bounce and body roll; Recognises verse · chorus and bridge of a song; Changes moves on the musical phrase (8-count); Completes a full 60-minute class
- **World Rhythms**: Bachata basic with hip motion; Cha-cha chassé; Samba bounce and samba walks; Soca jump and wine; Bhangra shoulder bounce; Belly dance hip shimmy; Hip-hop groove and step touch; Learns a new song routine in one class
- **High Energy**: High-impact jumps on every peak song; Squat and lunge toning tracks with good form; Full class at high intensity without breaks; Clean timing on fast tempo (140+ bpm); Knows 10+ class routines from memory; Adds own styling and energy to moves
- **Leader**: Demonstrates moves in mirror image; Gives non-verbal cues one count early; Leads one full song for the group; Builds a routine on verse-chorus structure; Offers modifications for beginners

#### Aerial hammock / aerial yoga (`aerial_yoga_levels`, palee)
Palee levels (no body grades students)

- **Intro**: Sets hammock height for seated and standing work; Safe mount into seat and safe exit; Supported standing postures (warrior · tree); Hammock-supported forward fold; Swinging seat and cocoon relaxation; Supported back bend over the hammock; Feet-on-floor assisted inversion
- **Level 1**: Basic invert (bat) from seat with control; Straddle inversion repeated 3 times; Diamond leg inversion; Gazelle; Butterfly; Buddha (lotus) inverted; Thigh lock; Double knee hook (diaper) wrap; Shoulder stand variation; Comes out of every invert slowly to the floor
- **Level 2**: Pullover from standing into front balance; Swan pose; Pullover 3-5 times in a row; Hip key; Cross back straddle entry; Higher inversions above the hammock seat; Back walkover off the hammock; Bomb drop; Waterfall; Linked sequence of 4 poses without touching the floor
- **Level 3**: Climb into the hammock from the floor; Hip key to inverted splits; Inverted crucifix; Star drop; Pinwheel or rollover sequence; Spinning poses with controlled momentum; Choreographed 2-minute routine
- **Level 4**: Dynamic drops linked into flows; One-arm and one-leg holds; Inverted strength skills (e.g. straddle-up without kick); Performance routine of 3+ minutes; Spots and cues a beginner safely

### Outdoor

#### Skateboarding levels (`skateboarding_levels`, palee)
Palee levels from Skateboard GB awards

- **Level 1**: Stance (regular or goofy) and pushing; Stopping with the foot and the tail; Carving turns; Falling safely with pads
- **Level 2**: Kickturns; Tic-tacs; Roll up and down a small ramp
- **Level 3**: Drop in on a mini ramp; Ollie on flat; Manual 2 metres
- **Level 4**: Ollie onto a curb; 50-50 grind; Frontside and backside 180
- **Level 5**: Kickflip; Pop shove-it; Rock to fakie on a ramp
- **Level 6**: Boardslide on a rail; Heelflip or varial flip; Line of three tricks

#### Indoor climbing levels (`climbing_nicas`, federation)
NICAS levels 1-5 (UK indoor climbing scheme)

- **New climber**: Fits a harness and helmet correctly; Figure-eight knot checked by a partner; Climbs a top-rope route and is lowered
- **Foundation climber**: Belays top-rope with an assisted device; Safe bouldering falls; Climbs smoothly with straight arms
- **Technical climber**: Footwork: edging and smearing; Flagging and drop knee
- **Lead climber**: Lead climbs and clips in sequence; Lead belays with dynamic catches; Takes practice lead falls
- **Advanced climber**: Plans training and route reading; Takes part in a competition

#### Bouldering grades (`bouldering_grades`, palee)
Palee levels by V-grade (Font in brackets)

- **V0 (4)**: Tops three different V0 problems
- **V1 (5)**: Tops three different V1 problems
- **V2 (5+)**: Tops three different V2 problems
- **V3 (6A)**: Tops three different V3 problems; Heel hooks and toe hooks
- **V4 (6B)**: Tops three different V4 problems; Dynos and coordination moves
- **V5 (6C)**: Tops three different V5 problems
- **V6 (7A)**: Tops three different V6 problems; Campus and fingerboard basics with care
- **V7 (7A+)**: Tops three different V7 problems
- **V8 (7B)**: Tops three different V8 problems
