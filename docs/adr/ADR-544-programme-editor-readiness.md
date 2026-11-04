# ADR-544: The programme editor: «Λείπουν N πράγματα» and copying weeks
Date: 2026-11-04
Status: Accepted

## Context
Board screens 1κ/1μ: instead of an error on «Δημοσίευση», a calm list of
what is missing that takes the coach there; and «Αντιγραφή στην επόμενη
εβδομάδα», filling only the empty days.

## Decision
1. **`readiness` on every staff programme payload** (`ProgrammeReadiness`,
   pure): `[{key, blocking, weeks}]` with `title`, `price`, `days` (blocking:
   the publish refuses them) and `empty_weeks` (with the 1-based weeks),
   `summary` (advisory). A cover is never required.
2. **Copying weeks stays in the editor.** The draft is saved whole
   (`PATCH draft_days`), so copying a week to the next one filling only empty
   days, copying to several weeks, reordering and deleting weeks are client
   operations on `draft_days`; the API validates the result as before
   (ADR-370). No new endpoint.
