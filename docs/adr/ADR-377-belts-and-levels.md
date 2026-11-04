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

## Diploma logo and coach signature Amendment — 2026-11-03 (option Γ)
The product owner chose option Γ of the diploma mockup: the box logo at the
top and the awarding coach's digital signature above a line with
«<name> · Coach». The diploma number stays and a withdrawn diploma still
prints «Ανακλήθηκε».

- **Logo**: the box's uploaded brand logo (ADR-121, `brand_logo_object_key`),
  read from storage when the PDF is drawn and fitted into 120 × 64 pt above
  the box name. No uploaded logo, a logo given as a link to another site
  (nothing is fetched from the network) or a WebP logo (PDF cannot hold
  WebP and there is no image library): only the name, as before. Solo
  coaches follow the same rule through their own business's brand.
- **Signature** («Υπογραφή για διπλώματα», Εγώ › Ρυθμίσεις, shown to anyone
  who is owner, admin or coach somewhere): one PNG or JPEG image per person,
  at most 512 KB and 60 × 20 to 1600 × 800 px; the browser turns a WebP, or
  a larger image, into a PNG first. Transparent PNG recommended. Uploaded
  as base64 JSON to `POST /api/me/diploma-signature`; `GET` (state and
  limits), `GET /image` (owner's preview) and `DELETE` are the person's
  own; nobody else ever receives the image except drawn inside a diploma.
- **Storage and security**: private media bucket, under the person's own
  prefix `users/<id>/diploma-signature/<id>.<ext>`, never a public URL.
  Table `diploma_signatures` (one current row, older ones retired) and the
  insert-only trail `diploma_signature_events` (`set`, `removed`), both
  readable only by the person and system sessions (forced RLS). The PDF is
  drawn server-side, reading the row as the system.
- **Snapshot, not current**: an award stores the coach's current
  `signature_id` when it is made (`rank_awards.signature_id`). Replacing the
  signature retires the old row and keeps its image, so issued diplomas do
  not change; removing it deletes every version, so every diploma drawn
  afterwards shows an empty line. Awards made before this change have no
  snapshot and show the empty line.
- **Lifecycle**: account deletion removes rows and images
  (`DiplomaSignatures.purge_person/1`); the person's data export has both
  tables (section `signatures`, object keys left out) and the images under
  `files/diploma-signature/`.
- **PDF**: `Palee.Pdf.image/6` with `Palee.Pdf.Image`, still with no
  dependency: JPEG as is (`DCTDecode`), PNG without alpha as its own data
  with PNG predictors, PNG with alpha (8-bit) unfiltered and split into an
  image and a soft mask; interlaced, 16-bit-with-alpha and other formats
  are left out.
- Migration `20270701100000_diploma_signatures.exs`;
  `Application.DiplomaSignatures`, `Ranks.Domain.SignaturePolicy`,
  `PaleeWeb.DiplomaSignatureController`; web
  `components/profile/DiplomaSignatureSection.tsx`.
