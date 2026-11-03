# ADR-367: The box's data export carries its photos and PDFs, and says when it is ready
Date: 2026-11-02
Status: Accepted

## Context
ADR-365 lets an owner download one ZIP of CSV files with all the box's
tables. It listed two gaps that the product owner (ANR) decided to close
when approving the screen «Λήψη των δεδομένων του box» (screen 3 of
`v31-mockups/board/w7-trust.html`):

- The ZIP must include photos and PDFs (split if large).
- One email when the file is ready.

The screen lives in Ρυθμίσεις › Επιχείρηση, between «Μεταβίβαση
ιδιοκτησίας» and «Κλείσιμο box», with three states: idle («Ετοίμασε το
αρχείο»), working (email when ready) and ready («Λήψη ZIP», 7 days, a new one
tomorrow). The closing card links to it.

## Decision
1. **Files.** After the CSV ZIP, `BoxDataExports` lists every object under the
   box's prefix (documents and PDFs, branding, media in both media buckets)
   except earlier exports (`exports/`), and packs them in key order into ZIP
   parts of at most `part_bytes` (`config :palee, :box_data_export`, default
   500 MB); a larger file gets a part of its own. Inside a part, files keep
   their path under a folder per kind (`documents/`, `branding/`, `media/`).
   Keys with `..` or empty segments are skipped; a file deleted since it was
   listed is left out. Pure rules in `BoxData.Domain.FilePacking`.
2. **Storage** (`20270513010000`): `box_data_exports.parts` (`name`, `key`,
   `bytes`, `sha256`, `files`), next to the CSV ZIP in the export's folder, so
   the existing expiry clean-up removes them.
3. **API.** The export view adds `parts` (each with a fresh short-lived
   download link while the export is ready).
4. **Email.** When the export is ready, the owner who asked gets one
   `:box_data_export_ready` email through the outbox (idempotency key per
   export), in their language (gettext domain `box_data`). It links to
   Settings, never to the file.
5. **Web.** `BoxDataExportCard` inside `OrganizationOwnerSettings`; the
   closing card's text links to it.

## Rationale
- Parts keep each download and each in-memory ZIP bounded.
- Members' avatars are their own (ADR-267) and stay out; everything else the
  box stores is the box's.

## Alternatives Considered
- **Streaming one ZIP of any size.** Needs a streaming upload to object
  storage; parts are simpler and friendlier for slow connections.
- **Links to the original files in a CSV.** They expire and break once the
  box leaves; rejected.

## Consequences
- The job downloads each file to a temporary folder and holds one part in
  memory while uploading it; very large boxes take longer.
- The export counts against the outbox's daily email budget (one email).

## Implementation Notes
- `BoxData.Domain.FilePacking`, `ExportPolicy.part_name/3`,
  `TenantObjectStorage.list_box_files/1` and `download_box_file/4`,
  `Email.Templates.BoxDataExportReady`.

## Amendment (v3.1 integration, 2026-11-03)

A key already under its kind's folder keeps it once inside the ZIP (`media/p1/photo.jpg`, never `media/media/…`).
