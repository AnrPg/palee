# Fitness benchmark anchors: audit and proposed values (2026-11-03)

Scope: the 23 benchmarks in `Palee.Pantheon.Domain.FitnessBenchmarks` (algorithm v2), the 7 body-weight-ratio lifts, and the age bands. Anchors: 20 «Ξεκίνησε» (3–6 months), 50 «Προπονημένος» (typical member, 1–2 years, 3–4×/week), 75 «Δυνατός» (top ~5 of a box), 95 «Αγωνιστικός» (local/national competitor, upper half).

**Status:** these are proposals. Treat them as correct until the reviewing coach objects. Every change is a new algorithm version, so nothing in this file is an edit of v2.

## How the values were set

| Anchor | What it is matched to (in order of weight) |
|---|---|
| 20 | Strength Level "novice" (stronger than 20% of logged lifters), adjusted down a little because Palee members are not self-selected lifters. For timed WODs: CrossFit.com "beginner/intermediate" tiers done Rx. |
| 50 | The mean of a peer-reviewed sample of 162 CrossFit members (Meier et al. 2021, *Sports*: 3.4 ± 1.9 years of CrossFit, 6.6 h/week), shifted a little slower or lighter because Palee's 50 means 1–2 years, not 3.4. Also the median of Mangine et al. 2018 (10,000 CrossFit Games profiles), with the same shift. Strength Level "intermediate" is used as an upper check. |
| 75 | About the 80th–90th percentile of the Mangine 2018 deciles and the Meier mean + 1 SD. Strength Level "advanced" is used as a check. |
| 95 | Below the top-quintile Games competitors (Mangine/Feito 10-year Games analysis: men back squat 202 kg, deadlift 232 kg; women 126 / 148 kg). Close to the CrossFit.com "elite" tier. |

Body-weight references are the ones already in the code: women 63 kg, men 82 kg. For comparison, the Meier sample averaged women 68.7 kg and men 84.9 kg.

---

## 1. All 23 benchmarks: current and proposed values

Units: kg (estimated 1RM), reps, and times in m:ss (Rx). Each cell lists the values for 20 / 50 / 75 / 95. "Kept" means the current value holds up against the sources.

### Strength and power (kg)

| Benchmark | Current W | Current M | **Proposed W** | **Proposed M** | Reason / source |
|---|---|---|---|---|---|
| Back squat | 40 / 65 / 95 / 125 | 60 / 100 / 140 / 180 | **45 / 75 / 100 / 125** | **75 / 120 / 155 / 190** | Current 50 is too low: the Meier members averaged M 141 ± 36 and W 93 ± 20, and Strength Level intermediate at 80 kg is 132, at 60 kg is 72. Men's 95 set to 190, just under the Games top quintile (202). [Meier 2021; SL; Mangine/Feito Games] |
| Front squat | 35 / 55 / 80 / 105 | 50 / 85 / 120 / 155 | **38 / 62 / 82 / 105** | **60 / 100 / 130 / 160** | Kept at 80–85% of the back squat, the usual front-to-back squat ratio. Fits SL (M 82 kg: novice 81 / intermediate 106 / advanced 136; W 63 kg: 45 / 62 / 81). [SL] |
| Deadlift | 50 / 85 / 120 / 160 | 80 / 130 / 180 / 230 | **60 / 95 / 125 / 150** | **95 / 150 / 190 / 230** | Meier means M 172 ± 37, W 114 ± 22. SL 82 kg: novice 122 / intermediate 158 / advanced 200. Men's 95 kept at 230 (Games top quintile 232). Women's 95 lowered to 150 (top quintile 148). [Meier; SL; Games analysis] |
| Bench press | 30 / 45 / 65 / 85 | 50 / 80 / 110 / 140 | **30 / 45 / 60 / 75** | **60 / 90 / 115 / 135** | Meier means M 106 ± 22, W 54 ± 13. CrossFitters train the bench little, so the 95 sits below SL elite. Women's 75/95 lowered, men's 20/50 raised. [Meier; SL] |
| Strict press | 20 / 35 / 48 / 62 | 35 / 55 / 75 / 95 | **25 / 35 / 45 / 55** | **40 / 60 / 75 / 90** | Meier means M 70 ± 16, W 43 ± 11. SL 82 kg: intermediate 64 / advanced 83; SL 63 kg: 32 / 44. Women's 20 is now the empty bar plus 5 kg. [Meier; SL] |
| Clean (also C&J and power clean) | 35 / 55 / 75 / 95 | 50 / 80 / 110 / 140 | **35 / 55 / 75 / 95 (kept)** | **55 / 90 / 115 / 140** | Meier C&J M 96 ± 26, W 63 ± 15. SL clean 82 kg: novice 75 / intermediate 95 / advanced 118 / elite 142. The women's values already match. [Meier; SL] |
| Snatch | 25 / 45 / 60 / 80 | 40 / 65 / 90 / 115 | **25 / 43 / 58 / 75** | **40 / 70 / 90 / 110** | Meier M 74 ± 21, W 48 ± 12. SL 63 kg: intermediate 43 / advanced 56 / elite 71. Snatch is kept at about 78% of the clean. Women's 95 at 80 was 84% of the clean, which is too high. [Meier; SL] |

### Gymnastics (reps)

| Benchmark | Current W | Current M | **Proposed W** | **Proposed M** | Reason / source |
|---|---|---|---|---|---|
| Pull-ups (max, kipping) | 1 / 6 / 15 / 28 | 3 / 12 / 25 / 40 | **kept** | **kept** | No published percentiles exist. The values are plausible against coach and community norms. A 1 at the women's 20 reflects that many women need months to get their first pull-up. [community] |
| HSPU (max) | 1 / 4 / 12 / 25 | 1 / 8 / 20 / 35 | **kept** | **kept** | Same as pull-ups. Diane at 75 (about 5:30) implies sets of 10–20, which is consistent. [CrossFit.com Diane tiers] |
| Muscle-ups | 1 / 2 / 6 / 12 | 1 / 4 / 10 / 20 | **kept** | **kept** | A first muscle-up is a milestone, and that 1 rep scores 20 points by design. [community] |
| Toes-to-bar | 2 / 12 / 25 / 45 | 3 / 15 / 30 / 50 | **2 / 10 / 22 / 35** | **3 / 12 / 25 / 40** | T2B max is usually at or below the pull-up max (same grip limit). The current 50 (15) was above the pull-up 50 (12), and 50 unbroken is Games level, not "upper half of local". Coach judgement only. [community] |
| Push-ups | 5 / 20 / 35 / 50 | 10 / 30 / 50 / 70 | **kept** | **kept** | ACSM/CSEP norms for ages 20–29 put "excellent" at about ≥36 (M) and ≥30 (W). Trained box members at 30/20 for the 50 anchor fit. [ACSM] |

### Monostructural (m:ss, lower is better)

| Benchmark | Current W | Current M | **Proposed W** | **Proposed M** | Reason / source |
|---|---|---|---|---|---|
| Row 500 m | 2:20 / 2:00 / 1:50 / 1:40 | 2:00 / 1:45 / 1:35 / 1:28 | **2:12 / 1:57 / 1:46 / 1:38** | **1:55 / 1:40 / 1:30 / 1:24** | **Statistics:** Concept2 2025 rankings, age 30–39. Men: p90 1:22.2, p75 1:28.2, p50 1:35.2, p25 1:44.3. Women: p90 1:36.7, p75 1:43.5, p50 1:53.4, p25 2:04.6. The current men's 50 (1:45) sat at the ranking p25, while the 2k 50 sat at the median. The 500 m is now placed at the same level as the 2k: 50 a little under the C2 median, 75 ≈ C2 p70, 95 ≈ C2 p90. The ×1.14–1.18 women/men time ratio matches C2 (median ×1.19). [Concept2 rankings; Seiler 1998] |
| Row 2k | 9:20 / 8:20 / 7:45 / 7:20 | 8:00 / 7:10 / 6:40 / 6:20 | **9:50 / 8:45 / 8:05 / 7:35** | **8:40 / 7:45 / 7:05 / 6:35** | **Statistics:** Concept2 2025, age 30–39. Men: p90 6:40.0, p75 6:58.8, p50 7:30.1, p25 8:02.3. Women: p90 7:28.9, p75 7:48.4, p50 8:26.4, p25 9:10.6. Concept2 rankers are keen rowers, so Palee's 50 sits a little slower than their median. In the C2 data the 2k pace is 13–17 s per 500 m slower than the 500 m time (more than Paul's law, +10 s). The proposed pairs keep that 15 s gap at every anchor; the current pairs had a 2–8 s gap, which is inconsistent. [Concept2 rankings; Paul's law] |
| Run 1 mile | 11:40 / 8:40 / 7:20 / 6:30 | 10:00 / 7:30 / 6:20 / 5:30 | **11:00 / 8:30 / 7:20 / 6:30** | **9:30 / 7:15 / 6:20 / 5:30** | Meier mile means are M 6:42 ± 1:21 and W 7:54 ± 1:25 (3.4 years of experience), so the 50 is slightly faster than before. The 20 is aligned with the 5k by Riegel (T₂ = T₁·(d₂/d₁)^1.06). [Meier; Riegel] |
| Run 5k | 35:00 / 29:00 / 24:30 / 21:40 | 30:00 / 25:00 / 21:00 / 18:30 | **35:00 / 28:30 / 24:30 / 21:40** | **30:00 / 24:00 / 21:00 / 18:30** | Riegel from the mile anchors gives 5k ≈ 3.33 × mile. The 50 is moved to 24:00 / 28:30. The other values were already consistent. [Riegel; Meier] |

### Metcon (m:ss, Rx; Cindy in rounds)

| Benchmark | Current W | Current M | **Proposed W** | **Proposed M** | Reason / source |
|---|---|---|---|---|---|
| Fran | 12:00 / 7:00 / 5:00 / 3:10 | 10:00 / 6:00 / 4:00 / 2:30 | **10:30 / 6:00 / 4:15 / 2:45** | **9:00 / 5:00 / 3:30 / 2:15** | Mangine 2018 medians: M 4:10, W 5:31; 80th percentile M 2:46. Meier means: M 5:10, W 6:02. CrossFit.com tiers: Rx "under 5", elite "under 3". The current 50 (6:00 / 7:00) was slower than every dataset. [Mangine 2018; Meier 2021; CrossFit.com] |
| Grace | 8:00 / 5:00 / 3:00 / 2:00 | 7:00 / 4:00 / 2:30 / 1:40 | **7:30 / 4:00 / 2:45 / 1:55** | **6:30 / 3:30 / 2:15 / 1:30** | Mangine medians: M 3:00, W 3:33; 80th percentile M 1:48, W 2:16. Meier means: M 3:53, W 4:11. CrossFit.com: Rx 5–7, elite under 2. [Mangine; Meier; CrossFit.com] |
| Helen | 17:00 / 13:00 / 10:40 / 9:20 | 15:00 / 11:30 / 9:30 / 8:20 | **16:00 / 12:00 / 10:00 / 8:40** | **14:00 / 10:30 / 9:00 / 7:40** | Mangine means: M 9:31, W 11:05. Meier means: M 10:11, W 11:39. CrossFit.com: Rx under 10, elite under 7. [Mangine; Meier; CrossFit.com] |
| Diane | 17:00 / 11:00 / 7:00 / 4:20 | 15:00 / 9:00 / 5:30 / 3:20 | **kept** | **kept** | Matches CrossFit.com (Rx under 6, elite under 3) and BoxRox/WODprep (intermediate 6–9, advanced 5–6, elite under 4). [CrossFit.com; BoxRox] |
| Isabel | 9:00 / 5:30 / 3:20 / 2:10 | 8:00 / 4:30 / 2:45 / 1:45 | **10:00 / 6:30 / 3:45 / 2:15** | **9:00 / 5:30 / 3:15 / 1:55** | The Rx load (61 / 43 kg) is 87% of the men's and 100% of the women's proposed 50-anchor snatch. Thirty reps at that intensity are singles every 10+ s. The current 4:30 / 5:30 is too fast for that population. ⚠ The women's 50 is barely feasible Rx; see §4. [load arithmetic vs. snatch anchors] |
| Karen | 17:00 / 11:30 / 8:30 / 7:00 | 15:00 / 10:00 / 7:30 / 6:00 | **15:00 / 10:30 / 8:00 / 6:15** | **14:00 / 9:30 / 7:00 / 5:30** | CrossFit.com: beginner 12–15, intermediate 8–11, Rx 6–7, elite under 5. The current 95 (6:00 / 7:00) is only the "Rx" tier, so it is moved toward competitive. [CrossFit.com] |
| Cindy (rounds) | 8 / 15 / 20 / 25 | 10 / 17 / 22 / 27 | **kept** | **kept** | Matches CrossFit.com (intermediate 8–10+ Rx, Rx 20+, elite 25+). [CrossFit.com] |

**Summary:** 16 of 23 benchmarks change. Kept fully: pull-ups, HSPU, muscle-ups, push-ups, Diane, Cindy. Kept for women only: clean.

---

## 2. Body-weight-ratio anchors (× body weight, rounded to 0.05)

The proposed kg anchors divided by 63 kg (women) and 82 kg (men). This keeps the ratio and kg paths consistent at the reference weight.

| Lift | Current W | **Proposed W** | Current M | **Proposed M** | SL check (W 60–70 kg / M 80 kg: novice–intermediate–advanced–elite) |
|---|---|---|---|---|---|
| Back squat | 0.65 / 1.05 / 1.50 / 2.00 | **0.70 / 1.20 / 1.60 / 2.00** | 0.75 / 1.20 / 1.70 / 2.20 | **0.90 / 1.45 / 1.90 / 2.30** | W 0.80–1.20–1.65–2.15; M 1.25–1.65–2.10–2.55 |
| Front squat | 0.55 / 0.85 / 1.25 / 1.65 | **0.60 / 1.00 / 1.30 / 1.65** | 0.60 / 1.05 / 1.45 / 1.90 | **0.75 / 1.20 / 1.60 / 1.95** | W 0.70–0.95–1.30–1.60; M 1.00–1.30–1.65–2.05 |
| Deadlift | 0.80 / 1.35 / 1.90 / 2.55 | **0.95 / 1.50 / 2.00 / 2.40** | 1.00 / 1.60 / 2.20 / 2.80 | **1.15 / 1.85 / 2.30 / 2.80** | W 1.00–1.40–1.90–2.45; M 1.50–1.95–2.45–3.00 |
| Bench press | 0.50 / 0.70 / 1.05 / 1.35 | **0.50 / 0.70 / 0.95 / 1.20** | 0.60 / 1.00 / 1.35 / 1.70 | **0.75 / 1.10 / 1.40 / 1.65** | W 0.50–0.75–1.10–1.45; M 0.95–1.20–1.55–1.90 |
| Strict press | 0.30 / 0.55 / 0.75 / 1.00 | **0.40 / 0.55 / 0.70 / 0.85** | 0.45 / 0.65 / 0.90 / 1.15 | **0.50 / 0.75 / 0.90 / 1.10** | W 0.35–0.50–0.70–0.95; M 0.55–0.80–1.00–1.25 |
| Clean | 0.55 / 0.85 / 1.20 / 1.50 | **0.55 / 0.85 / 1.20 / 1.50** (kept) | 0.60 / 1.00 / 1.35 / 1.70 | **0.65 / 1.10 / 1.40 / 1.70** | W 0.70–0.90–1.10–1.40; M 0.90–1.15–1.45–1.75 |
| Snatch | 0.40 / 0.70 / 0.95 / 1.25 | **0.40 / 0.70 / 0.90 / 1.20** | 0.50 / 0.80 / 1.10 / 1.40 | **0.50 / 0.85 / 1.10 / 1.35** | W 0.50–0.70–0.90–1.15; M 0.65–0.90–1.20–1.55 |

**Reading the check column:** Strength Level's population is people who log lifts in a strength app. Its "intermediate" is their median, so Palee's 50 (a typical box member) intentionally sits between SL novice and intermediate on the slow lifts (squat, deadlift, bench, press). On the Olympic lifts, Palee's 50 sits near SL intermediate, because box members practise those more than gym lifters do. Palee's 95 sits near SL advanced/elite for the squat and deadlift, and below SL elite for the bench and press, which CrossFit competitors do not specialise in.

**Lighter vs heavier athletes:** strength scales roughly with body mass^0.67 (allometric scaling; the basis of Sinclair, Wilks and IPF-GL). As a result, a plain ratio favours light athletes and penalises heavy ones:

- **Theory:** a 70 kg man and a 100 kg man of equal "level" differ in ratio by (100/70)^0.33 ≈ 1.12. The same 2.0× is therefore about 12% easier for the heavy man to reach in absolute kg terms, but about 12% harder in "real level" terms. Put differently, at the same ratio the lighter lifter is relatively weaker.
- **Observed:** Strength Level's own tables show a smaller effect at the median and a larger one at the top. Men's squat intermediate: 1.66× at 70 kg vs 1.63× at 100 kg. Men's squat elite: 2.64× vs 2.44×. Women's squat intermediate: 1.24× at 55 kg vs 1.10× at 80 kg.
- **Practical effect:** within ±15 kg of the reference weight the error is under about 5%, which is less than the gap between anchors. Outside that range (women over 80 kg, men over 100 kg or under 65 kg) the ratio misreads by 7–12%.
- **Suggestion (v3, optional):** scale the kg anchors as `kg_anchor × (bw / ref_bw)^0.67` instead of a fixed ratio. It reproduces the ratios above at 63/82 kg and treats light and heavy athletes fairly. Until then, the 2-decimal ratios above are the proposal.

---

## 3. Age percentages (one p per band; kg and reps × (1 − p), times × (1 + p))

### Proposed values

| Band | **Women p** | **Men p** |
|---|---|---|
| 35–39 | **5** | **5** |
| 40–44 | **8** | **10** |
| 45–49 | **13** | **15** |
| 50–54 | **20** | **20** |
| 55–59 | **26** | **25** |
| 60+ | **33** | **30** |

### Main evidence: CrossFit Open leaderboards (large-dataset statistics)

I computed this for this report from the public games.crossfit.com leaderboard API (`c3po.crossfit.com/api/leaderboards/v2`):

- **Sample:** 100 pages spread evenly over the whole Rx leaderboard, about 5,000 athletes per sex per year, with each athlete's age. The leaderboards hold 2023: 169k men / 133k women; 2024: 177k men / 144k women.
- **Comparison:** within each age band, the score at the **top 25% of that band's entrants** (scaled or no score counted as below). This is the decline at the *same peer percentile*, which is exactly what an age percentage must cancel.
- **Workouts used:** the 16–54 Rx standard is the same for all bands in these workouts. The 55+ divisions do lighter Rx, so they are not in these leaderboards.

Performance loss vs. ages 18–34, at the band's top 25%:

| Band | 23.2B thruster 1RM (strength) M / W | 23.2A burpee pull-ups + shuttle (conditioning) M / W | 24.2 row/DB-DL/DU AMRAP (mixed) M / W | Mean M / W |
|---|---|---|---|---|
| 35–39 | 4.2 / 6.2 | 3.6 / 5.2 | 7.6 / 5.1 | **5 / 5.5** |
| 40–44 | 7.4 / 6.2 | 8.8 / 8.6 | 12.0 / 10.6 | **9.5 / 8.5** |
| 45–49 | 14.0 / 14.6 | 13.9 / 12.9 | 20.7 / 12.5 | **16 / 13.5** |
| 50–54 | 20.0 / 15.4 | 16.1 / 18.1 | 22.8 / 22.1 | **20 / 18.5** |

(The top-10% and top-40% columns gave the same picture. 23.1 and 23.3 were left out because muscle-ups and HSPU turn their scores into steps. 24.1, a for-time workout with time-capped finishers, showed time +8 / 17 / 29 / 36% for men and +5 / 12 / 19 / 28% for women. It points the same way but is noisier.)

**Two findings settle the design question:**

1. **Strength and conditioning decline about equally in CrossFit athletes up to 54.** The thruster max and the burpee/shuttle workout are within 1–3 points of each other in every band. **One percentage per band is justified;** no per-domain split is needed up to 54.
2. **The peer-percentile decline among box athletes is larger than elite physiology suggests.** It is about 1% per year from 35 against about 0.7% per year in WMA running factors. This is because the masters population is partly late starters (a cohort effect). The proposal follows the Open data up to 54. Beyond 54 it follows the Open's own masters design (55+ Rx loads about 30% lighter) together with the physiology trend.

### Supporting evidence (meta-analyses and reviews first, then single studies)

| Source (type) | Finding | Implied loss per band (35–39 … 60+) |
|---|---|---|
| Mitchell et al. 2012, quantitative review (meta) | Muscle mass −0.47%/yr in men, −0.37%/yr in women. Strength falls 2–5× faster than mass. 3–4%/yr (men) and 2.5–3%/yr (women) by age 75. | Strength about 1–2%/yr from the 40s |
| Handgrip normative meta-analysis (114 studies, about 90,500 people) | Decline accelerates after 50 (about −0.37 kg/yr) | Steeper from 50–54 on |
| Reviews of VO₂max in masters athletes | −5 to −7% per decade while training is kept up; about −10–12% per decade for untrained people | Endurance about 0.5–0.7%/yr |
| WMA age-grading factors (statistics on records), 5000 m | M 1.000 / 0.965 / 0.930 / 0.895 / 0.860 / 0.826 (ages 35–60); W 1.000 / ~0.958 / 0.915 / 0.873 / 0.830 / 0.785 | M 1 / 5 / 8 / 12 / 15 / 19; W 1 / 5 / 10 / 14 / 19 / 23 |
| Concept2 2025 rankings (statistics), 2k median vs 30–39 | M +2.5% (40s), +4.7% (50s), +8.9% (60s); W +4.1 / +6.5 / +13.4% | Lower bound: lifelong rowers |
| Huebner et al. 2019, masters weightlifting (90th percentile) | Relative to 35: M 0.947 at 40, 0.723 at 60; W 0.952 at 40, 0.604 at 60, with an accelerated drop in women aged 48–58 | M 3 / 8 / 13 / 18 / 24 / 30; W 3 / 8 / 13 / 22 / 32 / 40 |
| Latella et al. (OpenPowerlifting statistics, longitudinal) | Competitive powerlifters lose under 0.5%/yr even after 60 | Upper limit for lifelong lifters only |
| CrossFit Open masters rules | Identical Rx for 16–54; 55+ about 30% lighter loads (e.g. 21.3: 95 → 65 lb men, 65 → 45 lb women) | A jump at 55 |

**Why the women's p is a little lower to 49 and higher from 55:** the Open data show women declining slightly less than men up to 49. Huebner (weightlifting) and WMA show women declining faster after menopause, so the women's p overtakes the men's from 55.

**Caveats:**

- The 60+ band is open-ended; 30% / 33% fits 60–65. A later 65+ band would need about 37% for men and 42% for women.
- If the coach wants the softer "physiology only" reading (lifelong trainers), use M 3 / 7 / 11 / 15 / 20 / 26 and W 3 / 7 / 11 / 17 / 24 / 31. The proposal above is the "peer percentile in real CrossFit populations" reading, which matches what members compare themselves with.

---

## 4. Cross-checks on the proposed values

**Relations within each level (all hold, W and M, kg and ratio):**

| Check | Women 20 / 50 / 75 / 95 | Men 20 / 50 / 75 / 95 |
|---|---|---|
| Front squat / back squat | 0.84 / 0.83 / 0.82 / 0.84 | 0.80 / 0.83 / 0.84 / 0.84 |
| Clean ≤ front squat | 35 < 38, 55 < 62, 75 < 82, 95 < 105 ✓ | 55 < 60, 90 < 100, 115 < 130, 140 < 160 ✓ |
| Snatch / clean | 0.71 / 0.78 / 0.77 / 0.79 | 0.73 / 0.78 / 0.78 / 0.79 |
| Strict press / bench | 0.83 / 0.78 / 0.75 / 0.73 | 0.67 / 0.67 / 0.65 / 0.67 |
| Deadlift / back squat | 1.33 / 1.27 / 1.25 / 1.20 | 1.27 / 1.25 / 1.23 / 1.21 |
| T2B vs pull-ups | 10 > 6 at the 50 anchor (accepted, see note) | 12 = 12 ✓ |

- **Front squat / back squat:** 0.80–0.85 is the usual range.
- **Snatch / clean:** weightlifters run 0.80–0.83. CrossFitters run a little lower because of snatch technique, so 0.73–0.79 is right.
- **Strict press / bench:** the women's press is closer to their bench, which is common.
- **Deadlift / back squat:** the ratio falls at higher levels as squat technique matures.
- **T2B vs. pull-ups:** for women, T2B (kipping, a hip-driven movement) is commonly achieved before a strong pull-up, so a women's T2B above the pull-up count is acceptable. For men the two are now equal at 50.

**Spacing:** every benchmark now gets smaller relative steps as the level rises, as performance distributions do:

- Back squat, men: 20 → 50 is +60%, 50 → 75 is +29%, 75 → 95 is +23%.
- Fran, men: 50 → 75 is −30%, 75 → 95 is −36%. The last step is wide because Fran times compress toward the elite.
- Two things are fixed: the row 2k/500 m inconsistency, and the T2B 50 being above the pull-up 50 for men.

**Women/men gaps per domain:**

| Domain | Women as a share of men (kg/reps) or time ratio | Literature |
|---|---|---|
| Lower-body lifts (squat, deadlift) | 0.60–0.66 | Review: adult women have 60–70% of men's lower-limb strength (Nuzzo 2023, as cited in the Nuzzo & Pinto 2025 meta-analysis). **Statistics:** 2023 Open 23.2B thruster 1RM, top 25% of 18–34: women 130 lb vs men 215 lb = 0.60. |
| Upper-body press/bench | 0.50–0.63 | Review: upper limb 50–60% (Nuzzo 2023); Miller 1993 about 52%. |
| Olympic lifts | 0.61–0.68 | – |
| Gymnastics reps | 0.33–0.80 | Largest gap at the low end (first pull-up or MU), which is expected. |
| Running time ratio | 1.16–1.19 | Recreational gap 15–20%; elite about 10–12%. |
| Rowing time ratio | 1.13–1.18 | Concept2 30–39 medians: 2k ×1.12, 500 m ×1.19. Power ratio about 1.5 → time ratio about 1.145. |
| Metcon time ratio | 1.10–1.22 | Fran 1.17–1.22 (load-heavy), Karen 1.07–1.14 (light ball, lower target), Helen 1.13–1.14. Matches Mangine medians: Fran 1.32 (self-reported), Grace 1.18, Helen 1.16. |

**Known limits to tell the coach about:**

1. **Isabel / Grace Rx at the women's 50 anchor:** 43 kg is the proposed 50-anchor snatch (100%) and 78% of the 50-anchor clean. Most «Προπονημένες» women cannot do Isabel Rx at all, so Isabel scores only describe the women who can. That is a valid reading, but it means Isabel will rarely produce a women's 50.
2. **Gymnastics anchors (pull-ups, HSPU, MU, T2B, push-ups):** no peer-reviewed percentile data exists for CrossFit populations. These are coach and community judgement and should be the coach's first check.
3. **Data sources:** both CrossFit datasets (Mangine 2018, Meier 2021) are self-reported and skewed toward engaged athletes. The proposals deliberately sit a little slower or lighter at the 50 anchor because of this.

---

## 5. Sources

Types: **meta-analysis** (meta-analysis, systematic or quantitative review) > **statistics** (large datasets) > **paper** (single peer-reviewed study) > **professional** > **community**.

### Meta-analysis / systematic review

- Mitchell WK et al. (2012). Sarcopenia, dynapenia, and the impact of advancing age on human skeletal muscle size and strength: a quantitative review. *Front Physiol* 3:260. https://pmc.ncbi.nlm.nih.gov/articles/PMC3429036/
- Handgrip strength normative values: systematic review and meta-analysis, 114 studies. PubMed 20553969. https://pubmed.ncbi.nlm.nih.gov/20553969
- Reviews of VO₂max decline in masters endurance athletes (−5 to −7% per decade while training is kept up). *J Sports Sci Med* 2007 review: https://www.jssm.org/jssm-06-477.xml-Fulltext ; Degens et al.: https://e-space.mmu.ac.uk/632468
- Nuzzo JL (2023). Narrative review of sex differences in muscle strength… *J Strength Cond Res*, as cited in Nuzzo & Pinto (2025), Sex differences in upper- and lower-limb muscle strength: a meta-analysis (adult figures: upper 50–60%, lower 60–70%). https://sportrxiv.org/index.php/server/preprint/view/451
- Hawley SE et al. (2023). Sex-based differences in resistance training in older adults: systematic review and meta-analysis. *Ageing Res Rev* 91:102023. https://pubmed.ncbi.nlm.nih.gov/37507092/
- Roberts BM et al. (2020). Sex differences in resistance training: systematic review and meta-analysis. https://pubmed.ncbi.nlm.nih.gov/32218059/
- Baker AB, Tang YQ (2010). Aging performance for masters records in athletics, swimming, rowing, cycling, triathlon and weightlifting (records analysis; rowing declines least). https://pubmed.ncbi.nlm.nih.gov/20845122

### Statistics (large datasets)

- **CrossFit Open 2023 and 2024 leaderboards** (official API, about 5,000 athletes sampled evenly per sex per year from 133k–177k entrants; percentile-by-age computed for this report). https://c3po.crossfit.com/api/leaderboards/v2/competitions/open/2024/leaderboards
- **Concept2 2025 rankings, 2000 m and 500 m**, published p90 / p75 / p50 / p25 by age and sex.
  - https://log.concept2.com/rankings/2025/rower/2000?age=30-39&gender=M
  - https://log.concept2.com/rankings/2025/rower/500?age=30-39&gender=F
- Mangine GT, Cebulla B, Feito Y (2018). Normative values for self-reported benchmark workout scores in CrossFit practitioners. *Sports Med Open* 4:39 (10,000 profiles; deciles). https://pmc.ncbi.nlm.nih.gov/articles/PMC6102159/
- Mangine GT et al. (2023). Normative scores for CrossFit Open workouts 2011–2022. *Sports* 11(2):24. https://pmc.ncbi.nlm.nih.gov/articles/PMC9960888/
- Latella C et al. Strength across ages in powerlifting (OpenPowerlifting data). https://ro.ecu.edu.au/ecuworks2022-2026/3457 ; preprint https://www.sportrxiv.org/index.php/server/preprint/view/218
- WMA age-grading tables (2012 corrected, reworked 2014; built from masters records). https://pzlam.pl/media/filer_public/35/86/35861393-f1f2-4d36-a783-75e3e05f2d7b/wma_age-grading-table.pdf
- Strength Level standards (crowd-sourced from user lifts; levels are user percentiles 5/20/50/80/95).
  - https://strengthlevel.com/strength-standards/squat/kg
  - https://strengthlevel.com/strength-standards/front-squat/kg
  - https://strengthlevel.com/strength-standards/deadlift/kg
  - https://strengthlevel.com/strength-standards/bench-press/kg
  - https://strengthlevel.com/strength-standards/shoulder-press/kg
  - https://strengthlevel.com/strength-standards/clean/kg
  - https://strengthlevel.com/strength-standards/power-clean/kg
  - https://strengthlevel.com/strength-standards/snatch/kg

### Paper (single peer-reviewed study)

- Meier N et al. (2021). Determination of a CrossFit benchmark performance profile. *Sports* 9(6). https://pmc.ncbi.nlm.nih.gov/articles/PMC8228530
- Mangine GT, Feito Y et al. Breaking down the CrossFit Games: a 10-year analysis. https://digitalcommons.kennesaw.edu/facpubs/4360
- Huebner M, Meltzer D, Perperoglou A (2019). Age-associated performance decline and sex differences in Olympic weightlifting. *MSSE*. https://pmc.ncbi.nlm.nih.gov/articles/PMC7028478
- Huebner M et al. (2020). The Masters athlete in Olympic weightlifting. *PLoS ONE*. https://journals.plos.org/plosone/article/file?id=10.1371%2Fjournal.pone.0243652&type=printable
- Seiler KS, Spirduso WW, Martin JE (1998). Gender differences in rowing performance and power with aging. *MSSE* 30:121–127. https://www.bisp-surf.de/Record/PU199803300375
- Ten-year longitudinal changes in muscle power, force and velocity (power −0.6%/yr young, −1.1–1.4%/yr middle-aged). https://pubmed.ncbi.nlm.nih.gov/36788413/
- Miller AE et al. (1993). *Eur J Appl Physiol* 66:254–262. Jaric S (2002). *Sports Med* 32:615–631 (allometric scaling). Riegel PS (1981). *American Scientist* 69:285–290. (cited from the literature; not fetched)

### Professional

- CrossFit.com benchmark pages ("good time" tiers).
  - https://www.crossfit.com/benchmark/fran
  - https://www.crossfit.com/benchmark/grace
  - https://www.crossfit.com/benchmark/helen
  - https://www.crossfit.com/benchmark/diane
  - https://www.crossfit.com/benchmark/karen
  - https://www.crossfit.com/benchmark/cindy
  - https://www.crossfit.com/benchmark/isabel
- IWF Masters technical rules (age groups, Sinclair-Meltzer factor). https://vektlofting.no/siteassets/dokumenter/lov-og-reglement/teknisk-reglement-iwf-masters.pdf
- World Masters Athletics, Age grading leaps forward. https://world-masters-athletics.org/news/age-grading-leaps-forward/
- Hong Kong indoor rowing standards by age. https://www.jara.or.jp/info/2019/2019hkric_annex2.pdf
- Kleshnev V, row2k: The effect of age on rowing power. https://www.row2k.com/features/6545/rowing-science-the-effect-of-a-rowers-age-on-rowing-power/
- Catalyst Athletics, What you can expect in weightlifting when you get older. https://www.catalystathletics.com/article/2078/What-You-Can-Expect-in-Weightlifting-When-You-Get-Older/
- BoxRox: Open 21.3 masters loads https://www.boxrox.com/?p=127213 ; The Girls tiers https://www.boxrox.com/crossfit-benchmark-workouts-the-girls/
- ACSM's Guidelines for Exercise Testing and Prescription, push-up norms (cited from the literature).

### Community

- USAWA, editorial and forum on the age formula. https://usawa.com/?p=30008
- CrossFit Data Lab, Open by age (rank-based; superseded by the leaderboard statistics above). https://crossfitdatalab.com/articles/crossfit-open-age-group-performance-analysis
- Concept2 forum, Decline with age. https://c2forum.com/viewtopic.php?p=432534
- StrongFirst forum, McCulloch coefficient. https://strongfirst.com/community/threads/mcculloch-coefficient-for-powerlifting.26251

### Not obtained

- The full Meltzer-Faber and McCulloch coefficient tables (bot-blocked or paywalled).
- BTWB and WODwell percentiles (not public).
- A raw OpenPowerlifting age curve (dataset too large for this pass; the Latella analysis is used instead).
