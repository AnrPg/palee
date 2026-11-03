# ADR-395: «Επίπεδο φυσικής κατάστασης» version 2 (body weight, age bands, change, display choice)
Date: 2026-11-03
Status: Accepted

## Context
ADR-358 scores each benchmark against fixed anchors (20/50/75/95 points) per sex. Members asked why
a light athlete scores low on lifts, why masters athletes are compared with 25-year-olds, how they
moved since last time, and whether they can hide the card. The product owner (ANR, 2026-11-03)
picked option A in all four sections of the mockup «Επίπεδο φυσικής κατάστασης v2»: lifts as a
multiple of body weight, age percentage per 5-year band from 35, the change next to the domain
label with a grey tick at the previous position, and a display choice «Όλα / Μόνο πρόοδος / Τίποτα»
the client's coach can override. A coach (xristoforos_rigas, Milos Method) reviews the ratio anchors
and sets the age percentages.

## Decision
- **Algorithm version 2** (`Pantheon.Domain.FitnessProfile`). With a body weight, the seven lifts
  (back/front squat, deadlift, bench, strict press, clean, snatch) are read as estimated 1RM (Epley)
  ÷ body weight against `ratio_anchors`; without it, the kg anchors stay. Each reading explains
  itself: `load`, `reps`, `basis` (`absolute`/`body_weight`), `ratio`, `body_weight_kg`, `age_band`,
  `age_percent` and `next` (points and the value that reaches the next anchor).
- **Age bands** 35–39 … 60+ ease the target: weights × (1 − p/100), reps likewise, times × (1 + p/100).
  The percentages come only from the reviewing coach; until they are filled in
  (`FitnessBenchmarks.age_ready?/0` is false) age changes nothing and the card does not ask for it.
  No invented defaults.
- **Change over a period.** `GET /api/me/fitness-profile?period=4w|12w|6m|1y|all` rebuilds the
  profile as it stood at the period start from the PR history (`as_of/3`) and adds
  `previous_score` / `change` per domain and overall. `all` or none: no change.
- **Account settings** `fitness_profile_settings` (migration `20270517000000`, owner-only forced
  RLS): `body_weight_kg` (25–300), `birth_year`, `display` (`all`, `progress_only`, `none`).
  `GET/PUT /api/me/fitness-profile/settings`. Exported with personal data, deleted with the account.
- **Coach override** `fitness_display_overrides` (per box and client, tenant RLS plus a client
  SELECT policy): `progress_only` or `none`. `GET/PUT /api/org/:slug/staff/clients/:user_id/fitness-display`
  only for a coach with an active coaching relationship (`403 not_your_client` otherwise;
  `view_client_training` to read, `manage_coaching` to change). The coach reads the client's weight,
  birth year and own choice through the narrow SECURITY DEFINER function
  `palee_coach_client_fitness_settings`, which pins only `search_path` (ANR: «personal
  trainer/coach (if assigned/exists) can see them»).
- **The strictest choice wins** (all < progress_only < none). When an override is stricter than the
  member's own, `display.set_by = "coach"` and the card says «Το όρισε ο coach σου».
  `progress_only` returns only each domain's direction (up/down/same), no scores; `none` returns no
  domains.

## Consequences
- Lift scores of light athletes rise and of heavy athletes fall once they enter a weight; the
  stepped «Γιατί;» shows the arithmetic so the number is never a black box.
- Age percentages stay empty until the coach review; filling them is a data change in
  `FitnessBenchmarks`, no migration.
- Supersedes ADR-358 only where it fixed kg anchors for everyone and showed no change.
