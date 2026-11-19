# ADR-670: The WOD's atlas inside the goals sheet

Status: Accepted (ANR, 2026-11-19)
Builds on: ADR-163 (WOD goals), ADR-164 (anatomy atlas), ADR-165 (a coach reads a client's depth), ADR-186 (branches), ADR-176 (gym days)

## Context

In «Στόχοι προπόνησης», «Άτλαντας ›» linked to `/journal/atlas?node=<first
muscle>`: only the WOD's first muscle, and on the member's Ημερολόγιο page.
For staff in the admin (e.g. the Αρχείο WOD preview) the page's guard allows
only member/athlete roles, so the owner was bounced to «/» and from there to
the admin home, losing the WOD they were looking at. ANR's picks from the
mockups (`/mnt/project-files/milos/wod-atlas/`): 1A, 2 «same as staff with
a full-atlas link», 3, 4 «programme load», 5 «the athlete's atlas», 6.

## Decision

- **All the WOD's muscles**: the atlas carries every muscle of the WOD with
  its role (primary, secondary, stabilizer). On the Ημερολόγιο page they
  travel as `?primary=a,b&secondary=c&stabilizer=d[&node=x]` and open a new
  view «Αυτό το WOD»: every muscle painted in its role, the body level lists
  them by role, a node says «Σε αυτό το WOD: …», «‹ Πίσω» returns.
- **Inside the sheet, for everyone**: «Άτλαντας ›» (or a muscle chip) opens
  the WOD's atlas as a second step of the same sheet, «‹ Στόχοι» returns and
  «Κλείσιμο» leaves the person where they were. Nobody changes page.
- **What it adds, by where the WOD sits** (`WodAtlasContext`):
  - member (class, Σήμερα, execution, own assignment): no coverage in the
    sheet; «Ολόκληρος ο άτλαντας ›» opens their own atlas in the Ημερολόγιο
    with the WOD's muscles.
  - Αρχείο WOD (`library`): the WOD alone: muscles, roles, what each muscle
    does, the box's exercises and videos.
  - a class on the schedule (`class`): «Φορτίο προγράμματος»,
    `GET /api/org/:slug/admin/schedule/slots/:id/programme-load`: the muscle
    groups the WODs of the same class type at the same branch aimed at in
    the 7 gym days before it, each WOD once per day, from its saved,
    inherited or suggested goals. Programme only, never members' entries.
    Capabilities `manage_workouts` or `run_classes`.
  - a WOD assigned to athletes (`athlete`): each athlete's coverage,
    `GET /api/org/:slug/staff/clients/:user_id/atlas`, the member atlas shape
    built with the ADR-165 coach read (`view_client_training`, active member,
    only entries shared with this gym's coaches, row security decides).
- **Staff never see their own atlas in the admin**; it lives only in the
  Ημερολόγιο, opened as member or athlete.

## Rationale

The sheet keeps context on phones and in the PWA, where a new tab or a page
change loses the preview. The programme load answers the coach's real
question («am I loading the same muscles again?») without touching personal
data. The athlete view reuses the existing, audited coach read.

## Consequences

- Shared atlas pieces moved to `components/anatomy/atlas/atlas-parts.tsx`;
  `WodAtlasView` is the in-sheet atlas.
- Staff see goals on a class in the schedule popup (`StaffWodGoalsStrip`).
- Pure domain `Palee.Anatomy.Domain.ProgrammeLoad` (heads roll up to groups,
  strongest role per WOD).
