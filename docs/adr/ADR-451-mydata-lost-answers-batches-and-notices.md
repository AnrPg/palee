# ADR-451: myDATA lost answers, batched sends, claim heartbeat and problem notices
Date: 2026-11-04
Status: Accepted

## Context
An audit of the ADR-243 myDATA reporting (ANR asked "is it functional, robust and tested?",
`/mnt/project-files/milos/mydata-audit-2026-11-04.md`) found these gaps:

- **Κ1:** if AADE registered a document but its answer was lost (timeout, 5xx, a dead
  worker), the retry sent it again. AADE answers "already sent", and that was stored as a
  rejection with no MARK.
- **Κ2:** a worker claimed 25 rows and sent them one by one, each with a 30 s timeout. That
  is up to 12.5 minutes, longer than the 10 minute claim timeout, so a second worker could
  take over rows that were still in flight.
- **Κ3:** nothing had ever talked to AADE itself. Every test used a stub.
- **Κ4:** nobody heard about refused or failed documents. Only a broken connection sent a
  notice.
- **Κ5:** the cron job swept every box inside a single job.
- **Κ6:** each document went in its own HTTP call.

## Decision
1. **Batches (Κ6, Κ2).** The claimed rows of a box go to AADE in one `InvoicesDoc`.
   `AuthorityGateway.submit/2` takes a list of invoices and returns one result per
   invoice, matched by AADE's 1-based `index`. An invoice with no answer is transient.
   The wire map carries `request_bodies`, so each attempt row keeps only its own document.
2. **Claim heartbeat (Κ2).** Before every call to the authority (a send or a look-up), the
   claims of the batch are renewed (`TransmissionStore.touch_claims/3`). A test guards that
   the longest single call is shorter than the claim timeout. That call is one send
   (`receive_timeout`) or one look-up through all its pages (`check_timeout ×
   max_lookup_pages`).
3. **Lost answers (Κ1).**
   - A row whose last attempt ended `transient` is first looked up with
     `AuthorityGateway.find/2`. For myDATA that is `GET /RequestTransmittedDocs` for the
     issue day and type, following the continuation token, and matching issuer ΑΦΜ,
     series, number, date and type. If AADE has the document, its MARK is taken and the
     row is accepted. Otherwise the document is sent.
   - If AADE answers "already sent" (`MyDataGateway.duplicate_codes/0`, today `228`), the
     result is `{:duplicate, errors}`, which triggers the same look-up. When nothing is
     found, the rejection stands.
4. **Notices (Κ4).**
   - New notification type `fiscal_documents_not_reported` (migration `20270706000000`),
     built by `ConnectionNotifier.documents_not_reported/3`. It goes to the people with
     `manage_billing`, at most once a day per connection and person, and links to
     Finance › Documents.
   - The staff home «Θέλει προσοχή» shows «N παραστατικά δεν έφτασαν στην ΑΑΔΕ», from the
     `counts` of `GET /admin/fiscal/transmissions` (rejected + failed).
5. **Per-box runs (Κ5).** The cron job only fans out. It calls `FiscalReporting.schedule/1`
   for each active box: a job of its own in production, and an inline run when background
   jobs are off.
6. **Live sandbox test (Κ3).** `test/palee/infrastructure/fiscal/my_data_live_test.exs`
   (`@tag :aade_live`) runs against `mydataapidev.aade.gr` and checks:
   - «Δοκιμή σύνδεσης» with the right key and with a wrong one;
   - a batch of two receipts;
   - a resend that must come back as a duplicate in a known code;
   - `find/2`, both found and not found.

   It runs only when `MYDATA_DEV_USER`, `MYDATA_DEV_KEY` and `MYDATA_DEV_VAT` are set, and
   `test_helper.exs` excludes it otherwise.

## Rationale
- Looking the document up before a resend prevents the duplicate. Handling "already sent"
  covers a lost answer the row did not know about, such as a worker that died after AADE
  answered.
- Matching on the document's own keys avoids recomputing AADE's UID hash, whose exact
  input order we would otherwise have to copy.
- A heartbeat bounds every claim by one call, whatever the batch size.

## Alternatives Considered
- **One row per claim.** This also fixes Κ2, but it costs one HTTP call per document and
  does nothing about Κ1.
- **A longer claim timeout alone.** It is fragile: it breaks again as soon as the timeouts
  or the batch size change.
- **Computing the UID and calling `RequestTransmittedDocs` by MARK range.** This needs
  AADE's exact UID formula.

## Consequences
- A recovered document has the MARK and UID that AADE lists. Its `qr_url` may be missing,
  because `RequestTransmittedDocs` may not return it.
- The duplicate code `228` and the look-up parameters are confirmed only by the live test.
  It has to run once with AADE test keys before the first Greek box goes live.
- The XSDs in `priv/fiscal/mydata/v2.0.1` contain fields up to roughly AADE v1.0.10. AADE
  has published v1.0.12, but aade.gr refused downloads from the cloud container (HTTP 403).
  Compare the two when the files can be fetched.

## Implementation Notes
- `SandboxAuthorityGateway.find/2` always answers `:not_found`, because the sandbox keeps
  nothing.
- `TransmissionPolicy` treats an unresolved `{:duplicate, _}` as a rejection.
