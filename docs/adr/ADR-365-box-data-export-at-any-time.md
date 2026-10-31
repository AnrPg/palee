# ADR-365: The box downloads all its data at any time
Date: 2026-10-31
Status: Accepted

## Context
CP-G5 is a check: "what happens if Palee closes, or we leave?" The backlog
asked to verify that a box (not only a person) can export all its data, and
to add an owner button with a full CSV export.

What existed:
- A person's own data: «Λήψη των δεδομένων μου» (ADR-267), JSON in a ZIP.
- The ADR-117 tenant export: complete, per bounded context, but only for the
  Palee team and only as the first stage of a purge (it suspends the box).
- Partial exports for owners: accounting exports (ADR-126/245), fiscal
  document exports, calendar feeds, journal exports, CSV imports.

So a box could not take its own data out without asking the Palee team.

## Decision
1. Owners (`manage_organization_lifecycle`) ask for «Λήψη των δεδομένων του
   box»: `POST /api/org/:slug/admin/data-exports` (202), list with
   `GET .../data-exports`. One in progress, one a day (a failed one does not
   count); the file is kept 7 days and every list call makes a fresh
   short-lived signed link. Files of expired exports are deleted when the
   next one is asked for.
2. `BoxDataExportJob` reads every bounded context through its own public
   `export_tenant_data/2` (the ADR-117 policies, so a new tenant table is
   covered the day it is declared), with a new scope
   `Palee.TenantData.BoxExportContext`: the box as `app.organization_id`
   and the owner who asked as `app.user_id`. `TableStore` accepts it for
   counting and exporting, never for purging.
3. The owner gets what row-level security lets the owner read. Members'
   personal tables (RLS keyed on the member: journal, wellness, body,
   devices, their own workout logs, PR records) are not the box's and are
   left out (`subject_user_ids` is always empty); each member downloads
   them through ADR-267. Secret columns declared by the policies (tokens,
   credentials, door secrets) never leave.
4. Format: one ZIP of CSV files (`<context>/<table>.csv`, UTF-8 with BOM,
   RFC 4180, nested values as JSON, a `'` before cells that a spreadsheet
   would run as a formula) plus `manifest.json` and `README.txt`. Stored
   privately under the box's prefix (`organizations/<id>/exports/box-data/`).
5. Records live in a new tenant table `box_data_exports`
   (`20270507010000`), owned by the small context `Palee.BoxData` with its
   own TenantDataPolicy (purged with the box).

## Rationale
- Reusing the ADR-117 per-context export means one source of truth for
  "all the box's tables", already enforced by `TenantTableCoverageTest`.
- CSV is what owners open (Excel, Sheets) and what other gym software
  imports; JSON stays the purge format for the Palee team.
- Reading as the owner (not as a vendor) keeps the export within what the
  owner may see in the app, so it cannot leak coach-private notes or a
  member's personal data.

## Alternatives Considered
- **Let owners download the ADR-117 export.** It needs a purge record and
  suspends the box. Rejected.
- **One CSV per screen (members, bookings, payments).** Never complete, and
  breaks with every new table. Rejected; a curated "members.csv" for
  switching software is listed as a follow-up.
- **Include members' personal data.** The box is not the controller of a
  member's journal or wellness entries (ADR-267). Rejected.

## Consequences
- The export is built in memory like ADR-117's; a very large box may need
  streaming later.
- Gaps found by the G5 check and not fixed here (listed for the backlog):
  1. Photos and document files (avatars, workout media, signed PDFs,
     invoice PDFs) are referenced by key but not inside the ZIP.
  2. No friendly "switching software" pack (members with package balances in
     the import format of ADR-254, i.e. the reverse of the CSV import).
  3. Member-logged results in personal tables (scores of members' own
     workouts) stay with the members; boxes see class results only.
  4. The export is not announced by email; the owner refreshes the list
     (no polling rule).
  5. Tables of a context without a TenantDataPolicy entry would be missing;
     `TenantTableCoverageTest` already fails on those.
- The screen (a card under Settings › «Προχωρημένα» or the owner's account
  area) waits for ANR's choice among the mockups.

## Implementation Notes
- `Palee.Application.BoxDataExports` (request/list/build/fail),
  `Palee.Workers.BoxDataExportJob`, `PaleeWeb.AdminDataExportController`,
  route capability `manage_organization_lifecycle`.
- The tenant table is in the tenancy audit, the store facade in
  `mix palee.architecture`, the context in `TenantDataContexts`.
- `BoxDataExportRLSTest` builds an export as the non-superuser runtime role.
