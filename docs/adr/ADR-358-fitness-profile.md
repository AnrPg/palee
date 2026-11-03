# ADR-358: An explainable fitness profile and «Τι να δουλέψεις»
Date: 2026-10-31
Status: Accepted

## Context
CP-D6: BTWB gives a «Fitness Level 1–100» and imbalances. The backlog asks for a score per ability
from the person's own results, «what to work on» from muscle and quality coverage, combined with load
(ADR-165), wellness and injuries, shown in the Journal and compared only with oneself (§4.4). The
caller asked for an explainable, versioned algorithm.

## Decision
- **Algorithm `fitness-profile` v1** (`Pantheon.Domain.FitnessProfile`, pure, computed on read):
  1. PRs whose names match a known benchmark (`Pantheon.Domain.FitnessBenchmarks`, 23 benchmarks,
     English and Greek aliases) with the right unit are read: weights as estimated 1RM (Epley, as
     ADR-285), reps and times as recorded.
  2. Points 0–100 interpolated between four anchors per division (20 started, 50 trained, 75 strong,
     95 competitive); without a division, the mean of both.
  3. A domain (strength, power, gymnastics, monostructural, metcon) is the mean of its benchmarks,
     a PR older than 365 days counting half; confidence by count.
  4. Overall = mean of the scored domains, only with two or more.
  5. `focus` (up to three): weakest domain (≥ 15 below the others), undertrained quality (< 25 % of
     the top quality over 12 weeks, ≥ 4 sessions, from `TrainingDepth`), stale benchmark, untested
     domain. Never a domain an active injury touches; `injury_caution` when an injury is active.
- Every score carries its `reasons` (benchmark, PR name, value, anchors, points, age), so the screen
  shows how it was reached.
- **`GET /api/me/fitness-profile?division=`** (account level, own data only, like Πρόοδος).
- Anchors are part of the version: changing one is a new version, never an edit.

## Rationale
Population anchors make one PR meaningful without other people's data; interpolation with visible
anchors is easy to explain. Computing on read follows ADR-285 (PRs are edited any time).

## Alternatives Considered
- Ranking against other Palee users (BTWB): violates §4.4 and needs cross-box data.
- Machine-learned scores: not explainable, no data yet.
- Storing scores: they would go stale with each PR edit.

## Consequences
- Free-named PRs that match no benchmark do not count; the screen lists the benchmarks to log.
- Injury → domain mapping is coarse (only the flag) until injuries carry a domain; open question.
- Anchors are coarse and need review by a coach (open question to the product owner).
