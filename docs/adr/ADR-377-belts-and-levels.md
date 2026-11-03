# ADR-377: Belts and levels («Βαθμοί») per discipline
Date: 2026-10-31
Status: Accepted

## Context
CP-E2 (P2): martial-arts belts and gymnastics levels (Zen Planner). Palee
has per-box scale levels (ADR-128) and a platform list of workout types in
families (ADR-275), which already include combat and gymnastics kinds.

## Decision
- New **Ranks** context with three tenant tables (forced RLS, tenant
  trigger): `rank_ladders` (name, **discipline = a workout type** of ADR-275,
  style `belt|level`, optional class types whose attendance counts),
  `ranks` (ordered; name, colour from a fixed belt palette, up to 10
  stripes, requirements `min_classes`, `min_days`, `skills`, an optional
  **scale level** of the box the rank suggests — ADR-128 reuse) and
  `rank_awards` (rank, stripes, date, awarded by, note, skills ticked,
  diploma number `R-<year>-<8 hex>`, withdrawal with reason).
- **Templates** («Πρότυπα»): BJJ adult belts, karate kyu belts, gymnastics
  levels 1–10; everything editable afterwards (calm default).
- **Promotions** are always a coach's decision. Progress shows classes
  attended since the current rank (from class history, in the ladder's
  class types), days in rank and the skills list; `ready` only says the
  counted requirements are met. An award goes up the ladder or adds
  stripes; going down is a withdrawal with a reason, kept in the history.
- **Diploma** («Δίπλωμα»): an A4 PDF drawn with `Palee.Pdf` (box, person,
  ladder, rank, stripes, date, who awarded it, number; «Ανακλήθηκε» when
  withdrawn).
- API: admin `/rank-ladders` (`manage_settings` or `manage_workouts`);
  staff `/clients/:user_id/ranks`, `/rank-awards/:id/revoke|certificate`
  (`manage_coaching`, own clients for coaches, ADR-100); member
  `/me/ranks`, `/me/ranks/awards/:id/certificate` (own awards only).

## Rationale
Discipline as a workout type keeps ranks in the same families as stats,
badges and colours; a rank → scale level link turns "Level 4" into a
sensible default scale without a second vocabulary.

## Alternatives Considered
- Reusing scale levels as ranks: scale levels describe a workout variant,
  not a person's standing; they have no history or requirements.
- Automatic promotion when requirements are met: coaches in every dojo
  decide promotions themselves.

## Consequences
- Ranks are the box's records: tenant export/purge (purge order 63), in the
  person's GDPR export (training); kept with an anonymised profile.
- Class history rows now carry `class_type_id`.
- Screens after ANR's pick (W9 board: setup, coach promotion, member card).
- The backlog says "only if pilots ask": the API costs nothing until a box
  creates a ladder; the settings entry stays under «Προχωρημένα».

## Implementation Notes
- Migration `20270602400000_rank_ladders.exs`; `Palee.Ranks`,
  `Application.RankLadders`, `RankPromotions`, `MyRanks`, `RankStanding`,
  `RankCertificates`.
